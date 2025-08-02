import 'dart:async';
import 'dart:typed_data';

import '../abstract/index.dart';

/// 用于把另一个文件系统里的某个子文件夹作为一个新文件系统
class AliasFileSystem extends IFileSystem {
  AliasFileSystem({
    required this.fileSystem,
    Path? subDirectory,
    String loggerName = 'AliasFileSystem',
  }) : subDirectory = subDirectory ?? Path.rootPath;

  final IFileSystem fileSystem;
  final Path subDirectory;

  /// 将alias路径转换为底层文件系统的实际路径
  Path _convertToRealPath(Context context, Path aliasPath) {
    final logger = context.logger;
    if (subDirectory.isRoot) {
      logger.trace(
        'Converting alias path (root case): $aliasPath -> $aliasPath',
      );
      return aliasPath;
    }
    // 将alias路径与子目录路径合并
    final realPath = Path([...subDirectory.segments, ...aliasPath.segments]);
    logger.trace(
      'Converting alias path: '
      '$aliasPath -> $realPath (subdirectory: $subDirectory)',
    );
    return realPath;
  }

  /// 将底层文件系统的路径转换为alias路径
  Path _convertFromRealPath(Context context, Path realPath) {
    final logger = context.logger;
    if (subDirectory.isRoot) {
      logger.trace('Converting real path (root case): $realPath -> $realPath');
      return realPath;
    }

    // 检查路径是否在子目录下
    if (realPath.segments.length < subDirectory.segments.length) {
      logger.warning(
        'Real path is too short: $realPath '
        '(subdirectory depth: ${subDirectory.segments.length})',
      );
      throw ArgumentError('Real path is not under subdirectory');
    }

    // 验证路径前缀匹配
    for (int i = 0; i < subDirectory.segments.length; i++) {
      if (realPath.segments[i] != subDirectory.segments[i]) {
        logger.warning(
          'Path prefix mismatch at segment $i: '
          'expected "${subDirectory.segments[i]}", '
          'got "${realPath.segments[i]}"',
        );
        throw ArgumentError('Real path is not under subdirectory');
      }
    }

    // 移除子目录前缀
    final aliasPath = Path(
      realPath.segments.sublist(subDirectory.segments.length),
    );
    logger.trace(
      'Converting real path: '
      '$realPath -> $aliasPath (removed subdirectory: $subDirectory)',
    );
    return aliasPath;
  }

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      'Copying: $source -> $destination '
      '(overwrite: ${options.overwrite}, recursive: ${options.recursive})',
    );
    final realSource = _convertToRealPath(context, source);
    final realDestination = _convertToRealPath(context, destination);
    logger.debug('Real paths: $realSource -> $realDestination');
    return fileSystem.copy(
      context,
      realSource,
      realDestination,
      options: options,
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      'Creating directory: $path (createParents: ${options.createParents})',
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.createDirectory(context, realPath, options: options);
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    final logger = context.logger;
    logger.debug('Deleting: $path (recursive: ${options.recursive})');
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.delete(context, realPath, options: options);
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    final logger = context.logger;
    logger.trace('Checking existence: $path');
    final realPath = _convertToRealPath(context, path);
    return fileSystem.exists(context, realPath, options: options);
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final logger = context.logger;
    logger.debug('Listing directory: $path (recursive: ${options.recursive})');
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');

    var itemCount = 0;
    await for (final status in fileSystem.list(
      context,
      realPath,
      options: options,
    )) {
      itemCount++;
      // 将真实路径转换为alias路径
      final aliasPath = _convertFromRealPath(context, status.path);

      yield FileStatus(
        path: aliasPath,
        isDirectory: status.isDirectory,
        size: status.size,
        mimeType: status.mimeType,
      );
    }
    logger.debug('Listed $itemCount items in directory: $path');
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      'Moving: $source -> $destination '
      '(overwrite: ${options.overwrite}, recursive: ${options.recursive})',
    );
    final realSource = _convertToRealPath(context, source);
    final realDestination = _convertToRealPath(context, destination);
    logger.debug('Real paths: $realSource -> $realDestination');
    return fileSystem.move(
      context,
      realSource,
      realDestination,
      options: options,
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
      'Opening read stream: $path '
      '(start: ${options.start}, end: ${options.end})',
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.openRead(context, realPath, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) {
    final logger = context.logger;
    logger.debug('Opening write stream: $path (mode: ${options.mode})');
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.openWrite(context, realPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      'Reading bytes: $path (start: ${options.start}, end: ${options.end})',
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.readAsBytes(context, realPath, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final logger = context.logger;
    logger.trace('Getting status: $path');
    final realPath = _convertToRealPath(context, path);
    final realStatus = await fileSystem.stat(
      context,
      realPath,
      options: options,
    );

    if (realStatus == null) {
      logger.trace('Status not found: $path');
      return null;
    }

    logger.trace(
      'Status found: $path (isDirectory: ${realStatus.isDirectory}, '
      'size: ${realStatus.size})',
    );
    // 将真实路径转换为alias路径
    return FileStatus(
      path: path,
      isDirectory: realStatus.isDirectory,
      size: realStatus.size,
      mimeType: realStatus.mimeType,
    );
  }

  @override
  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      'Writing bytes: $path (${data.length} bytes, mode: ${options.mode})',
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug('Real path: $realPath');
    return fileSystem.writeBytes(context, realPath, data, options: options);
  }
}
