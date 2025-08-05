import 'dart:async';

import '../../abstract/index.dart';
import '../../helper/filesystem_helper.dart';
import 'operation.dart';

/// 装饰器Sink，在写入完成后执行回调
class _CacheInvalidatingSink implements StreamSink<List<int>> {
  _CacheInvalidatingSink({
    required this.originalSink,
    required this.onClose,
    required this.context,
  });

  final StreamSink<List<int>> originalSink;
  final Future<void> Function() onClose;
  final Context context;

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
    final logger = context.logger;
    try {
      // 先关闭原始Sink
      await originalSink.close();
      // 然后执行缓存失效回调
      await onClose();
      logger.trace('写入流关闭，缓存已失效');
    } catch (e) {
      logger.warning('关闭流时发生错误', error: e);
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
  }) : _cacheOperation = CacheManager(
         originFileSystem: originFileSystem,
         cacheFileSystem: cacheFileSystem,
         cacheDir: cacheDir,
         blockSize: blockSize,
         readAheadBlocks: readAheadBlocks,
         enableReadAhead: enableReadAhead,
       );

  final IFileSystem originFileSystem;
  final CacheManager _cacheOperation;

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '拷贝文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'options': options.toString(),
      },
    );
    await originFileSystem.copy(context, source, destination, options: options);
    // 目标文件的缓存可能需要失效
    await _cacheOperation.invalidateCache(context, destination);
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    return originFileSystem.createDirectory(context, path, options: options);
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '删除文件或目录',
      metadata: {'path': path.toString(), 'options': options.toString()},
    );
    await originFileSystem.delete(context, path, options: options);
    // 删除文件后使其缓存失效
    await _cacheOperation.invalidateCache(context, path);
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    return originFileSystem.exists(context, path, options: options);
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return originFileSystem.list(context, path, options: options);
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '移动文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'options': options.toString(),
      },
    );
    await originFileSystem.move(context, source, destination, options: options);
    // 移动操作会影响源文件和目标文件的缓存
    await _cacheOperation.invalidateCache(context, source);
    await _cacheOperation.invalidateCache(context, destination);
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    return originFileSystem.stat(context, path, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug('打开写入流', metadata: {'path': path.toString()});
    final originalSink = await originFileSystem.openWrite(
      context,
      path,
      options: options,
    );

    // 创建一个装饰器Sink，在写入完成后刷新缓存
    return _CacheInvalidatingSink(
      originalSink: originalSink,
      onClose: () => _cacheOperation.invalidateCache(context, path),
      context: context,
    );
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '打开读取流',
      metadata: {'path': path.toString(), 'options': options.toString()},
    );
    return _cacheOperation.openReadWithBlockCache(context, path, options);
  }
}
