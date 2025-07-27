import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../abstract/index.dart';

/// 用于把另一个文件系统里的某个子文件夹作为一个新文件系统
class AliasFileSystem extends IFileSystem {
  AliasFileSystem({
    required this.fileSystem,
    Path? subDirectory,
    String loggerName = 'AliasFileSystem',
  }) : subDirectory = subDirectory ?? Path.rootPath,
       logger = Logger(loggerName) {
    logger.info(
      'AliasFileSystem initialized with subdirectory: '
      '${subDirectory?.toString() ?? "/"}',
    );
  }

  @override
  final Logger logger;
  final IFileSystem fileSystem;
  final Path subDirectory;

  /// 将alias路径转换为底层文件系统的实际路径
  Path _convertToRealPath(Path aliasPath) {
    if (subDirectory.isRoot) {
      logger.finest(
        'Converting alias path (root case): $aliasPath -> $aliasPath',
      );
      return aliasPath;
    }
    // 将alias路径与子目录路径合并
    final realPath = Path([...subDirectory.segments, ...aliasPath.segments]);
    logger.finest(
      'Converting alias path: '
      '$aliasPath -> $realPath (subdirectory: $subDirectory)',
    );
    return realPath;
  }

  /// 将底层文件系统的路径转换为alias路径
  Path _convertFromRealPath(Path realPath) {
    if (subDirectory.isRoot) {
      logger.finest('Converting real path (root case): $realPath -> $realPath');
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
    logger.finest(
      'Converting real path: '
      '$realPath -> $aliasPath (removed subdirectory: $subDirectory)',
    );
    return aliasPath;
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    logger.fine(
      'Copying: $source -> $destination '
      '(overwrite: ${options.overwrite}, recursive: ${options.recursive})',
    );
    final realSource = _convertToRealPath(source);
    final realDestination = _convertToRealPath(destination);
    logger.fine('Real paths: $realSource -> $realDestination');
    return fileSystem.copy(realSource, realDestination, options: options);
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    logger.fine(
      'Creating directory: $path (createParents: ${options.createParents})',
    );
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.createDirectory(realPath, options: options);
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    logger.fine('Deleting: $path (recursive: ${options.recursive})');
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.delete(realPath, options: options);
  }

  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    logger.finest('Checking existence: $path');
    final realPath = _convertToRealPath(path);
    return fileSystem.exists(realPath, options: options);
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    logger.fine('Listing directory: $path (recursive: ${options.recursive})');
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');

    var itemCount = 0;
    await for (final status in fileSystem.list(realPath, options: options)) {
      itemCount++;
      // 将真实路径转换为alias路径
      final aliasPath = _convertFromRealPath(status.path);

      yield FileStatus(
        path: aliasPath,
        isDirectory: status.isDirectory,
        size: status.size,
        mimeType: status.mimeType,
      );
    }
    logger.fine('Listed $itemCount items in directory: $path');
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) {
    logger.fine(
      'Moving: $source -> $destination '
      '(overwrite: ${options.overwrite}, recursive: ${options.recursive})',
    );
    final realSource = _convertToRealPath(source);
    final realDestination = _convertToRealPath(destination);
    logger.fine('Real paths: $realSource -> $realDestination');
    return fileSystem.move(realSource, realDestination, options: options);
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    logger.fine(
      'Opening read stream: $path '
      '(start: ${options.start}, end: ${options.end})',
    );
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.openRead(realPath, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) {
    logger.fine('Opening write stream: $path (mode: ${options.mode})');
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.openWrite(realPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    logger.fine(
      'Reading bytes: $path (start: ${options.start}, end: ${options.end})',
    );
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.readAsBytes(realPath, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    logger.finest('Getting status: $path');
    final realPath = _convertToRealPath(path);
    final realStatus = await fileSystem.stat(realPath, options: options);

    if (realStatus == null) {
      logger.finest('Status not found: $path');
      return null;
    }

    logger.finest(
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
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) {
    logger.fine(
      'Writing bytes: $path (${data.length} bytes, mode: ${options.mode})',
    );
    final realPath = _convertToRealPath(path);
    logger.fine('Real path: $realPath');
    return fileSystem.writeBytes(realPath, data, options: options);
  }
}
