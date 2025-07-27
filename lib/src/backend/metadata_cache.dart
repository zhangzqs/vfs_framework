import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import 'metadata_cache_operation.dart';

class MetadataCacheFileSystem extends IFileSystem with FileSystemHelper {
  MetadataCacheFileSystem({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    Duration maxCacheAge = const Duration(minutes: 30),
    int largeDirectoryThreshold = 1000,
    String loggerName = 'MetadataCacheFileSystem',
  }) : logger = Logger(loggerName) {
    logger.info(
      'MetadataCacheFileSystem initialized with maxCacheAge: $maxCacheAge, '
      'largeDirectoryThreshold: $largeDirectoryThreshold, '
      'cacheDir: ${cacheDir.toString()}, using hierarchical cache structure',
    );
    _cacheOperation = MetadataCacheOperation(
      logger: logger,
      originFileSystem: originFileSystem,
      cacheFileSystem: cacheFileSystem,
      cacheDir: cacheDir,
      maxCacheAge: maxCacheAge,
      largeDirectoryThreshold: largeDirectoryThreshold,
    );
  }

  @override
  final Logger logger;
  final IFileSystem originFileSystem;
  late final MetadataCacheOperation _cacheOperation;

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    logger.fine('Copying ${source.toString()} to ${destination.toString()}');
    await originFileSystem.copy(source, destination, options: options);
    // 目标文件的缓存需要刷新，源文件缓存保持不变
    await _cacheOperation.handleFileSystemChange(destination);
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    logger.fine('Creating directory ${path.toString()}');
    await originFileSystem.createDirectory(path, options: options);
    // 新创建的目录需要刷新缓存
    await _cacheOperation.handleFileSystemChange(path);
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    if (!options.recursive) {
      logger.fine('Deleting ${path.toString()}');
      await originFileSystem.delete(path, options: options);
      // 删除文件后使其缓存失效
      await _cacheOperation.handleFileSystemChange(path, isDelete: true);
    } else {
      logger.fine('Recursively deleting ${path.toString()}');
      return deleteImplByNonRecursive(
        nonRecursiveDelete:
            (Path path, {DeleteOptions options = const DeleteOptions()}) async {
              await originFileSystem.delete(
                path,
                options: const DeleteOptions(recursive: false),
              );
              await _cacheOperation.handleFileSystemChange(
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
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    // exists可以通过stat实现
    final status = await _cacheOperation.getFileStatus(path);
    return status != null;
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    logger.fine('Moving ${source.toString()} to ${destination.toString()}');
    await originFileSystem.move(source, destination, options: options);
    // 移动操作：源文件缓存失效，目标文件缓存刷新
    await _cacheOperation.handleFileSystemChange(source, isDelete: true);
    await _cacheOperation.handleFileSystemChange(destination);
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.openRead(path, options: options);
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
    return _MetadataInvalidatingSink(
      originalSink: originalSink,
      onClose: () => _cacheOperation.handleFileSystemChange(path),
    );
  }

  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.readAsBytes(path, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    return _cacheOperation.getFileStatus(path);
  }

  Stream<FileStatus> nonRecursiveList(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return _cacheOperation.listDirectory(path);
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    return listImplByNonRecursive(
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  @override
  Future<void> writeBytes(
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    await originFileSystem.writeBytes(path, data, options: options);
    // 写入完成后刷新缓存
    await _cacheOperation.handleFileSystemChange(path);
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
