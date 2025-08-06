import 'dart:async';
import 'dart:typed_data';

import 'package:vfs_framework/src/logger/index.dart';

import '../../abstract/index.dart';
import '../../helper/filesystem_helper.dart';
import 'operation.dart';

class MetadataCacheFileSystem extends IFileSystem with FileSystemHelper {
  MetadataCacheFileSystem({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    Duration maxCacheAge = const Duration(days: 7),
    int largeDirectoryThreshold = 1000,
    Logger? asyncTaskLogger,
  }) {
    _cacheOperation = MetadataCacheOperation(
      originFileSystem: originFileSystem,
      cacheFileSystem: cacheFileSystem,
      cacheDir: cacheDir,
      maxCacheAge: maxCacheAge,
      largeDirectoryThreshold: largeDirectoryThreshold,
    );
    _cacheOperation.startLRUCleanup(asyncTaskLogger ?? Logger.defaultLogger);
  }

  final IFileSystem originFileSystem;
  late final MetadataCacheOperation _cacheOperation;

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    final logger = context.logger;
    logger.debug('Copying ${source.toString()} to ${destination.toString()}');
    await originFileSystem.copy(context, source, destination, options: options);
    // 目标文件的缓存需要刷新，源文件缓存保持不变
    await _cacheOperation.handleFileSystemChange(context, destination);
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    final logger = context.logger;
    logger.debug('Creating directory ${path.toString()}');
    await originFileSystem.createDirectory(context, path, options: options);
    // 新创建的目录需要刷新缓存
    await _cacheOperation.handleFileSystemChange(context, path);
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final logger = context.logger;
    if (!options.recursive) {
      logger.debug('Deleting ${path.toString()}');
      await originFileSystem.delete(context, path, options: options);
      // 删除文件后使其缓存失效
      await _cacheOperation.handleFileSystemChange(
        context,
        path,
        isDelete: true,
      );
    } else {
      final logger = context.logger;
      logger.debug('Recursively deleting ${path.toString()}');
      return deleteImplByNonRecursive(
        context,
        nonRecursiveDelete:
            (
              Context context,
              Path path, {
              DeleteOptions options = const DeleteOptions(),
            }) async {
              await originFileSystem.delete(
                context,
                path,
                options: const DeleteOptions(recursive: false),
              );
              await _cacheOperation.handleFileSystemChange(
                context,
                path,
                isDelete: true,
              );
            },
        nonRecursiveList: nonRecursiveList,
        path: path,
        options: options,
      );
    }
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    // exists可以通过stat实现
    final status = await _cacheOperation.getFileStatus(context, path);
    return status != null;
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    final logger = context.logger;
    logger.debug('Moving ${source.toString()} to ${destination.toString()}');
    await originFileSystem.move(context, source, destination, options: options);
    // 移动操作：源文件缓存失效，目标文件缓存刷新
    await _cacheOperation.handleFileSystemChange(
      context,
      source,
      isDelete: true,
    );
    await _cacheOperation.handleFileSystemChange(context, destination);
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.openRead(context, path, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final originalSink = await originFileSystem.openWrite(
      context,
      path,
      options: options,
    );

    // 创建一个装饰器Sink，在写入完成后刷新缓存
    return _MetadataInvalidatingSink(
      originalSink: originalSink,
      onClose: () => _cacheOperation.handleFileSystemChange(context, path),
    );
  }

  @override
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.readAsBytes(context, path, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    return _cacheOperation.getFileStatus(context, path);
  }

  Stream<FileStatus> nonRecursiveList(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return _cacheOperation.listDirectory(context, path);
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return listImplByNonRecursive(
      context,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  @override
  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    await originFileSystem.writeBytes(context, path, data, options: options);
    // 写入完成后刷新缓存
    await _cacheOperation.handleFileSystemChange(context, path);
  }

  @override
  Future<void> dispose(Context context) async {
    // 关闭缓存操作
    _cacheOperation.dispose();
  }
}

/// 装饰器Sink，在写入完成后执行回调
class _MetadataInvalidatingSink implements StreamSink<List<int>> {
  _MetadataInvalidatingSink({
    required this.originalSink,
    required this.onClose,
  });

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
    // 然后执行缓存刷新回调
    await onClose();
  }

  @override
  Future<void> get done => originalSink.done;
}
