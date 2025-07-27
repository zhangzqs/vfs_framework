import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:logging/logging.dart';
import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';

/// 在cacheDir中，针对srcPath构建分层缓存目录路径，双层目录结构，有利于文件系统查询性能
Path _buildCacheHashDir(Logger logger, Path cacheDir, Path srcPath) {
  /// 基于SHA256生成文件路径的hash值，16个字符
  String generatePathHash(Path path) {
    // hash为长度为16的字符串
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.finest('Generated hash for ${path.toString()}: $hash');
    return hash;
  }

  final hash = generatePathHash(srcPath);

  // 使用前2位作为第一层目录 (每个level1下4096种可能)
  final level1 = hash.substring(0, 3);
  // 使用第3-4位作为第二层目录 (每个level2下4096种可能)
  final level2 = hash.substring(3, 6);
  // 第三级目录使用剩余的hash值
  final level3 = hash.substring(6);
  // 构建分层路径: cacheDir/abc/def/1234ef567890/
  final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

  logger.finest(
    'Built hierarchical cache path for hash $hash: '
    '${hierarchicalPath.toString()}',
  );
  return hierarchicalPath;
}

class BlockCacheFileSystem extends IFileSystem with FileSystemHelper {
  BlockCacheFileSystem({
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    this.blockSize = 1024 * 1024, // 默认块大小为1MB
    String loggerName = 'BlockCacheFileSystem',
  }) : logger = Logger(loggerName) {
    logger.info(
      'BlockCacheFileSystem initialized with blockSize: $blockSize bytes, '
      'cacheDir: ${cacheDir.toString()}, using hierarchical cache structure',
    );
  }

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
    logger.fine('Copying ${source.toString()} to ${destination.toString()}');
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
    logger.fine('Deleting ${path.toString()}');
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
    logger.fine('Moving ${source.toString()} to ${destination.toString()}');
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
    logger.fine('Opening write stream for ${path.toString()}');
    final originalSink = await originFileSystem.openWrite(
      path,
      options: options,
    );

    // 创建一个装饰器Sink，在写入完成后刷新缓存
    return _CacheInvalidatingSink(
      originalSink: originalSink,
      onClose: () => _invalidateCache(path),
      logger: logger,
    );
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    logger.fine('Opening read stream for ${path.toString()} with block cache');
    return _openReadWithBlockCache(path, options);
  }

  /// 实现块缓存的读取
  Stream<List<int>> _openReadWithBlockCache(
    Path path,
    ReadOptions options,
  ) async* {
    try {
      logger.finest('Starting block-cached read for ${path.toString()}');

      // 获取文件状态信息
      final fileStatus = await originFileSystem.stat(path);
      if (fileStatus == null || fileStatus.isDirectory) {
        throw FileSystemException.notAFile(path);
      }

      final fileSize = fileStatus.size ?? 0;
      if (fileSize == 0) {
        logger.finest('File is empty: ${path.toString()}');
        return; // 空文件直接返回
      }

      // 计算读取范围
      final startOffset = options.start ?? 0;
      final endOffset = options.end ?? fileSize;
      final readLength = endOffset - startOffset;

      if (readLength <= 0) {
        logger.warning(
          'Invalid read range for ${path.toString()}: '
          'start=$startOffset, end=$endOffset',
        );
        return; // 无效的读取范围
      }

      // 计算涉及的块范围
      final startBlockIdx = startOffset ~/ blockSize;
      final endBlockIdx = (endOffset - 1) ~/ blockSize;
      final totalBlocks = endBlockIdx - startBlockIdx + 1;

      logger.finest(
        'Reading ${path.toString()}: blocks $startBlockIdx-$endBlockIdx '
        '($totalBlocks blocks)',
      );

      // 生成文件路径的hash
      final cacheHashDir = _buildCacheHashDir(logger, cacheDir, path);

      // 逐块读取数据
      var currentOffset = startOffset;
      var remainingBytes = readLength;

      for (var blockIdx = startBlockIdx; blockIdx <= endBlockIdx; blockIdx++) {
        if (remainingBytes <= 0) break;

        // 获取当前块的数据
        final blockData = await _getBlockData(cacheHashDir, blockIdx, path);

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

      logger.finest('Completed block-cached read for ${path.toString()}');
    } catch (e) {
      logger.warning('Block-cached read failed for ${path.toString()}: $e');
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: '读取文件失败: ${path.toString()}, 错误: $e',
        path: path,
      );
    }
  }

  /// 获取指定块的数据（带缓存）
  Future<Uint8List> _getBlockData(
    Path cacheHashDir,
    int blockIdx,
    Path originalPath,
  ) async {
    // 构建分层缓存路径：<cacheHashDir>/blocks/<blockIdx> 和 <cacheHashDir>/meta.json
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());
    final cacheMetaPath = cacheHashDir.join('meta.json');

    try {
      // 首先检查缓存是否存在
      if (await cacheFileSystem.exists(cacheBlockPath)) {
        // 验证缓存完整性和hash冲突
        if (await _validateCacheIntegrity(cacheMetaPath, originalPath)) {
          final cachedData = await _readFullBlock(
            cacheFileSystem,
            cacheBlockPath,
          );
          if (cachedData != null) {
            logger.finest(
              'Cache hit for ${originalPath.toString()}, block $blockIdx',
            );
            return cachedData;
          }
        } else {
          logger.warning(
            'Cache integrity check failed for ${originalPath.toString()}, '
            'possible hash collision detected, invalidating cache',
          );
          await _invalidateCache(originalPath);
        }
      }

      // 缓存不存在或验证失败，从原始文件系统读取
      logger.finest(
        'Cache miss for ${originalPath.toString()}, block $blockIdx, '
        'reading from origin',
      );
      final blockData = await _readBlockFromOrigin(originalPath, blockIdx);

      // 异步写入缓存（不阻塞读取）
      _writeToCacheAsync(
        cacheHashDir,
        cacheBlocksDir,
        cacheBlockPath,
        cacheMetaPath,
        originalPath,
        blockIdx,
        blockData,
      );

      return blockData;
    } catch (e) {
      logger.warning(
        'Error reading block cache for ${originalPath.toString()}: $e',
      );
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

    logger.finest('Reading block $blockIdx from origin for ${path.toString()}');
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
      logger.warning('Failed to read cached block ${path.toString()}: $e');
      return null; // 读取失败返回null
    }
  }

  /// 异步写入缓存（不阻塞主流程）
  void _writeToCacheAsync(
    Path cacheHashDir,
    Path cacheBlocksDir,
    Path cacheBlockPath,
    Path cacheMetaPath,
    Path originalPath,
    int blockIdx,
    Uint8List data,
  ) {
    // 使用Future.microtask确保不阻塞当前操作
    Future.microtask(() async {
      try {
        // 确保缓存目录结构存在
        if (!await cacheFileSystem.exists(cacheHashDir)) {
          await cacheFileSystem.createDirectory(
            cacheHashDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        if (!await cacheFileSystem.exists(cacheBlocksDir)) {
          await cacheFileSystem.createDirectory(
            cacheBlocksDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        // 写入块数据
        final sink = await cacheFileSystem.openWrite(
          cacheBlockPath,
          options: const WriteOptions(mode: WriteMode.overwrite),
        );

        sink.add(data);
        await sink.close();

        // 更新或创建meta.json文件
        await _updateCacheMetadata(cacheMetaPath, originalPath, blockIdx);

        logger.finest(
          'Cache written successfully for ${originalPath.toString()}, '
          'block $blockIdx',
        );
      } catch (e) {
        logger.warning(
          'Failed to write cache for ${originalPath.toString()}, '
          'block $blockIdx: $e',
        );
        // 静默处理缓存写入错误，不影响主流程
      }
    });
  }

  /// 验证缓存完整性，防止hash冲突
  Future<bool> _validateCacheIntegrity(Path metaPath, Path originalPath) async {
    try {
      if (!await cacheFileSystem.exists(metaPath)) {
        logger.finest(
          'No metadata file found for cache validation: ${metaPath.toString()}',
        );
        return false; // 元数据文件不存在
      }

      // 读取元数据
      final metaBytes = <int>[];
      await for (final chunk in cacheFileSystem.openRead(metaPath)) {
        metaBytes.addAll(chunk);
      }

      final metaJson =
          json.decode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      final cachedPath = metaJson['filePath'] as String?;
      final cachedSize = metaJson['fileSize'] as int?;
      final cachedBlockSize = metaJson['blockSize'] as int?;

      // 验证路径是否匹配
      if (cachedPath != originalPath.toString()) {
        logger.warning(
          'Path mismatch in cache metadata: '
          'expected ${originalPath.toString()}, '
          'got $cachedPath',
        );
        return false; // 路径不匹配，可能是hash冲突
      }

      // 验证块大小是否匹配
      if (cachedBlockSize != blockSize) {
        logger.warning(
          'Block size mismatch in cache metadata: expected $blockSize, '
          'got $cachedBlockSize',
        );
        return false; // 块大小不匹配，需要重新缓存
      }

      // 获取原文件的状态信息进行验证
      final originalStat = await originFileSystem.stat(originalPath);
      if (originalStat == null) {
        logger.warning(
          'Original file does not exist: ${originalPath.toString()}',
        );
        return false; // 原文件不存在
      }

      // 验证文件大小是否匹配
      if (cachedSize != null && originalStat.size != cachedSize) {
        logger.warning(
          'File size changed, cache is outdated for: '
          '${originalPath.toString()}',
        );
        return false; // 文件大小变化，缓存过期
      }

      logger.finest('Cache validation passed for ${originalPath.toString()}');
      return true;
    } catch (e) {
      logger.warning('Cache integrity validation failed: $e');
      return false;
    }
  }

  /// 更新缓存元数据
  Future<void> _updateCacheMetadata(
    Path metaPath,
    Path originalPath,
    int blockIdx,
  ) async {
    try {
      // 获取原文件信息
      final originalStat = await originFileSystem.stat(originalPath);
      if (originalStat == null) {
        logger.warning(
          'Cannot get original file stat for metadata: '
          '${originalPath.toString()}',
        );
        return;
      }

      final fileSize = originalStat.size ?? 0;
      final totalBlocks = (fileSize + blockSize - 1) ~/ blockSize; // 向上取整

      Map<String, dynamic> metadata = {};

      // 如果元数据文件已存在，先读取现有数据
      if (await cacheFileSystem.exists(metaPath)) {
        try {
          final existingMetaBytes = <int>[];
          await for (final chunk in cacheFileSystem.openRead(metaPath)) {
            existingMetaBytes.addAll(chunk);
          }
          metadata =
              json.decode(utf8.decode(existingMetaBytes))
                  as Map<String, dynamic>;
        } catch (e) {
          logger.warning('Failed to read existing metadata, creating new: $e');
          metadata = {};
        }
      }

      // 更新元数据
      metadata.addAll({
        'filePath': originalPath.toString(),
        'fileSize': fileSize,
        'blockSize': blockSize,
        'totalBlocks': totalBlocks,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0',
      });

      // 更新缓存的块信息
      final cachedBlocks =
          (metadata['cachedBlocks'] as List<dynamic>?) ?? <dynamic>[];
      if (!cachedBlocks.contains(blockIdx)) {
        cachedBlocks.add(blockIdx);
        cachedBlocks.sort(); // 保持有序
      }
      metadata['cachedBlocks'] = cachedBlocks;

      // 写入元数据文件
      final metaJson = json.encode(metadata);
      final metaBytes = utf8.encode(metaJson);

      final sink = await cacheFileSystem.openWrite(
        metaPath,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      sink.add(metaBytes);
      await sink.close();

      logger.finest(
        'Cache metadata updated for ${originalPath.toString()}, '
        'block $blockIdx',
      );
    } catch (e) {
      logger.warning('Failed to update cache metadata: $e');
      // 元数据更新失败不影响缓存数据本身
    }
  }

  /// 使指定文件的缓存失效
  Future<void> _invalidateCache(Path path) async {
    try {
      final cacheHashDir = _buildCacheHashDir(logger, cacheDir, path);

      logger.fine(
        'Invalidating cache for path: ${path.toString()}, '
        'cache dir: ${cacheHashDir.toString()}',
      );

      // 检查缓存目录是否存在
      if (await cacheFileSystem.exists(cacheHashDir)) {
        // 删除整个hash目录（包含blocks子目录和meta.json文件）
        await cacheFileSystem.delete(
          cacheHashDir,
          options: const DeleteOptions(recursive: true),
        );
        logger.fine('Cache invalidated successfully for: ${path.toString()}');

        // 尝试清理空的父级目录（可选的清理操作）
        await _cleanupEmptyParentDirs(cacheHashDir);
      } else {
        logger.finest('No cache found to invalidate for: ${path.toString()}');
      }
    } catch (e) {
      logger.warning('Failed to invalidate cache for ${path.toString()}: $e');
      // 静默处理缓存清理错误，不影响主流程
    }
  }

  /// 清理空的父级目录（避免留下大量空目录）
  Future<void> _cleanupEmptyParentDirs(Path cacheHashDir) async {
    try {
      // 获取父级目录路径
      final level2Dir = cacheHashDir.parent; // xx/yy/ 目录
      final level1Dir = level2Dir?.parent; // xx/ 目录

      if (level2Dir != null && await cacheFileSystem.exists(level2Dir)) {
        // 检查level2目录是否为空
        final level2Items = <FileStatus>[];
        await for (final item in cacheFileSystem.list(level2Dir)) {
          level2Items.add(item);
        }

        if (level2Items.isEmpty) {
          await cacheFileSystem.delete(level2Dir);
          logger.finest('Cleaned up empty level2 dir: ${level2Dir.toString()}');

          // 检查level1目录是否也为空
          if (level1Dir != null && await cacheFileSystem.exists(level1Dir)) {
            final level1Items = <FileStatus>[];
            await for (final item in cacheFileSystem.list(level1Dir)) {
              level1Items.add(item);
            }

            if (level1Items.isEmpty) {
              await cacheFileSystem.delete(level1Dir);
              logger.finest(
                'Cleaned up empty level1 dir: ${level1Dir.toString()}',
              );
            }
          }
        }
      }
    } catch (e) {
      // 静默处理清理错误，不影响主要功能
      logger.finest('Failed to cleanup empty parent dirs: $e');
    }
  }
}

/// 装饰器Sink，在写入完成后执行回调
class _CacheInvalidatingSink implements StreamSink<List<int>> {
  _CacheInvalidatingSink({
    required this.originalSink,
    required this.onClose,
    required this.logger,
  });

  final StreamSink<List<int>> originalSink;
  final Future<void> Function() onClose;
  final Logger logger;

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
    try {
      // 先关闭原始Sink
      await originalSink.close();
      // 然后执行缓存失效回调
      await onClose();
      logger.finest('Write stream closed and cache invalidated');
    } catch (e) {
      logger.warning('Error during stream close: $e');
      rethrow;
    }
  }

  @override
  Future<void> get done => originalSink.done;
}
