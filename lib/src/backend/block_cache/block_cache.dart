import 'dart:async';

import 'package:logging/logging.dart';
import '../../abstract/index.dart';
import '../../helper/filesystem_helper.dart';
import 'operation.dart';

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

class BlockCacheFileSystem extends IFileSystem with FileSystemHelper {
  BlockCacheFileSystem({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    int blockSize = 1024 * 1024, // 默认块大小为1MB
    int readAheadBlocks = 2, // 预读
    bool enableReadAhead = true, // 默认启用预读
    String loggerName = 'BlockCacheFileSystem',
  }) : logger = Logger(loggerName) {
    logger.info(
      'BlockCacheFileSystem initialized with blockSize: $blockSize bytes, '
      'readAheadBlocks: $readAheadBlocks, enableReadAhead: $enableReadAhead, '
      'cacheDir: ${cacheDir.toString()}, using hierarchical cache structure',
    );
    _cacheOperation = CacheOperation(
      logger: logger,
      originFileSystem: originFileSystem,
      cacheFileSystem: cacheFileSystem,
      cacheDir: cacheDir,
      blockSize: blockSize,
      readAheadBlocks: readAheadBlocks,
      enableReadAhead: enableReadAhead,
    );
  }

  @override
  final Logger logger;
  final IFileSystem originFileSystem;
  late final CacheOperation _cacheOperation;

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    logger.fine('Copying ${source.toString()} to ${destination.toString()}');
    await originFileSystem.copy(source, destination, options: options);
    // 目标文件的缓存可能需要失效
    await _cacheOperation.invalidateCache(destination);
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
    await _cacheOperation.invalidateCache(path);
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
    await _cacheOperation.invalidateCache(source);
    await _cacheOperation.invalidateCache(destination);
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
      onClose: () => _cacheOperation.invalidateCache(path),
      logger: logger,
    );
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    logger.fine('Opening read stream for ${path.toString()} with block cache');
    return _cacheOperation.openReadWithBlockCache(path, options);
  }
}
