import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';

class BlockCacheFileSystem extends IFileSystem with FileSystemHelper {
  BlockCacheFileSystem({
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    this.blockSize = 1024 * 1024, // 默认块大小为1MB
    String loggerName = 'BlockCacheFileSystem',
  }) : logger = Logger(loggerName);
  @override
  final Logger logger;
  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final int blockSize;

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    await originFileSystem.copy(source, destination, options: options);
    // 目标文件的缓存可能需要失效
    await _invalidateCache(destination);
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    return originFileSystem.createDirectory(path, options: options);
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    await originFileSystem.delete(path, options: options);
    // 删除文件后使其缓存失效
    await _invalidateCache(path);
  }

  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    return originFileSystem.exists(path, options: options);
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return originFileSystem.list(path, options: options);
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    await originFileSystem.move(source, destination, options: options);
    // 移动操作会影响源文件和目标文件的缓存
    await _invalidateCache(source);
    await _invalidateCache(destination);
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    return originFileSystem.stat(path, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final originalSink = await originFileSystem.openWrite(
      path,
      options: options,
    );

    // 创建一个装饰器Sink，在写入完成后刷新缓存
    return _CacheInvalidatingSink(
      originalSink: originalSink,
      onClose: () => _invalidateCache(path),
    );
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    return _openReadWithBlockCache(path, options);
  }

  /// 实现块缓存的读取
  Stream<List<int>> _openReadWithBlockCache(
    Path path,
    ReadOptions options,
  ) async* {
    try {
      // 获取文件状态信息
      final fileStatus = await originFileSystem.stat(path);
      if (fileStatus == null || fileStatus.isDirectory) {
        throw FileSystemException.notAFile(path);
      }

      final fileSize = fileStatus.size ?? 0;
      if (fileSize == 0) {
        return; // 空文件直接返回
      }

      // 计算读取范围
      final startOffset = options.start ?? 0;
      final endOffset = options.end ?? fileSize;
      final readLength = endOffset - startOffset;

      if (readLength <= 0) {
        return; // 无效的读取范围
      }

      // 计算涉及的块范围
      final startBlockIdx = startOffset ~/ blockSize;
      final endBlockIdx = (endOffset - 1) ~/ blockSize;

      // 生成文件路径的hash
      final pathHash = _generatePathHash(path);

      // 逐块读取数据
      var currentOffset = startOffset;
      var remainingBytes = readLength;

      for (var blockIdx = startBlockIdx; blockIdx <= endBlockIdx; blockIdx++) {
        if (remainingBytes <= 0) break;

        // 获取当前块的数据
        final blockData = await _getBlockData(pathHash, blockIdx, path);

        // 计算当前块内的偏移量和读取长度
        final blockStartOffset = blockIdx * blockSize;
        final offsetInBlock = max(0, currentOffset - blockStartOffset);
        final bytesToRead = min(blockSize - offsetInBlock, remainingBytes);

        // 提取需要的部分数据
        final dataToYield = blockData.sublist(
          offsetInBlock,
          offsetInBlock + bytesToRead,
        );

        yield dataToYield;

        currentOffset += bytesToRead;
        remainingBytes -= bytesToRead;
      }
    } catch (e) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: '读取文件失败: ${path.toString()}, 错误: $e',
        path: path,
      );
    }
  }

  /// 生成文件路径的hash值
  String _generatePathHash(Path path) {
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);

    // 使用简单的hash算法
    var hash = 0;
    for (final byte in bytes) {
      hash = ((hash << 5) - hash + byte) & 0xFFFFFFFF;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 获取指定块的数据（带缓存）
  Future<Uint8List> _getBlockData(
    String pathHash,
    int blockIdx,
    Path originalPath,
  ) async {
    // 构建缓存路径
    final cacheBlockPath = cacheDir.join(pathHash).join(blockIdx.toString());

    try {
      // 首先尝试从缓存读取
      if (await cacheFileSystem.exists(cacheBlockPath)) {
        final cachedData = await _readFullBlock(
          cacheFileSystem,
          cacheBlockPath,
        );
        if (cachedData != null) {
          return cachedData;
        }
      }

      // 缓存不存在或读取失败，从原始文件系统读取
      final blockData = await _readBlockFromOrigin(originalPath, blockIdx);

      // 异步写入缓存（不阻塞读取）
      _writeToCacheAsync(cacheBlockPath, blockData);

      return blockData;
    } catch (e) {
      // 缓存读取失败，回退到原始文件系统
      return await _readBlockFromOrigin(originalPath, blockIdx);
    }
  }

  /// 从原始文件系统读取指定块
  Future<Uint8List> _readBlockFromOrigin(Path path, int blockIdx) async {
    final blockStart = blockIdx * blockSize;
    final readOptions = ReadOptions(
      start: blockStart,
      end: blockStart + blockSize,
    );

    final chunks = <int>[];
    await for (final chunk in originFileSystem.openRead(
      path,
      options: readOptions,
    )) {
      chunks.addAll(chunk);
    }

    return Uint8List.fromList(chunks);
  }

  /// 从缓存文件系统读取完整块
  Future<Uint8List?> _readFullBlock(IFileSystem filesystem, Path path) async {
    try {
      final chunks = <int>[];
      await for (final chunk in filesystem.openRead(path)) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (e) {
      return null; // 读取失败返回null
    }
  }

  /// 异步写入缓存（不阻塞主流程）
  void _writeToCacheAsync(Path cachePath, Uint8List data) {
    // 使用Future.microtask确保不阻塞当前操作
    Future.microtask(() async {
      try {
        // 确保缓存目录存在
        final cacheParentDir = cachePath.parent;
        if (cacheParentDir != null &&
            !await cacheFileSystem.exists(cacheParentDir)) {
          await cacheFileSystem.createDirectory(
            cacheParentDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        // 写入缓存数据
        final sink = await cacheFileSystem.openWrite(
          cachePath,
          options: const WriteOptions(mode: WriteMode.overwrite),
        );

        sink.add(data);
        await sink.close();
      } catch (e) {
        // 静默处理缓存写入错误，不影响主流程
        // 可以在这里添加日志记录
      }
    });
  }

  /// 使指定文件的缓存失效
  Future<void> _invalidateCache(Path path) async {
    try {
      final pathHash = _generatePathHash(path);
      final cacheHashDir = cacheDir.join(pathHash);

      // 检查缓存目录是否存在
      if (await cacheFileSystem.exists(cacheHashDir)) {
        // 删除整个hash目录下的所有缓存块
        await cacheFileSystem.delete(
          cacheHashDir,
          options: const DeleteOptions(recursive: true),
        );
      }
    } catch (e) {
      // 静默处理缓存清理错误，不影响主流程
      // 可以在这里添加日志记录
    }
  }
}

/// 装饰器Sink，在写入完成后执行回调
class _CacheInvalidatingSink implements StreamSink<List<int>> {
  _CacheInvalidatingSink({required this.originalSink, required this.onClose});

  final StreamSink<List<int>> originalSink;
  final Future<void> Function() onClose;

  @override
  void add(List<int> data) {
    originalSink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    originalSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return originalSink.addStream(stream);
  }

  @override
  Future<void> close() async {
    // 先关闭原始Sink
    await originalSink.close();
    // 然后执行缓存失效回调
    await onClose();
  }

  @override
  Future<void> get done => originalSink.done;
}
