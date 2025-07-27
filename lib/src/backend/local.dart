import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import '../helper/mime_type_helper.dart';

class LocalFileSystem extends IFileSystem with FileSystemHelper {
  LocalFileSystem({Directory? baseDir, String loggerName = 'LocalFileSystem'})
    : baseDir = baseDir ?? Directory.current,
      logger = Logger(loggerName) {
    logger.info(
      'LocalFileSystem initialized with baseDir: ${this.baseDir.path}',
    );
  }

  @override
  final Logger logger;

  /// 本地文件系统的基础目录
  final Directory baseDir;

  // 将抽象Path转换为本地文件系统路径
  String _toLocalPath(Path path) {
    final localPath = p.join(baseDir.path, p.joinAll(path.segments));
    logger.finest(
      'Converting abstract path ${path.toString()} to local path: $localPath',
    );
    return localPath;
  }

  // 将本地路径转换为抽象Path
  Path _toPath(String localPath) {
    logger.finest('Converting local path $localPath to abstract path');
    // 计算相对于baseDir的相对路径
    String relative = p.relative(localPath, from: baseDir.path);

    // 处理特殊情况：根目录
    if (relative == '.') {
      logger.finest('Local path is root directory, returning empty path');
      return Path([]);
    }

    // 使用path包分割路径
    final abstractPath = Path(p.split(relative));
    logger.finest('Converted to abstract path: ${abstractPath.toString()}');
    return abstractPath;
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    logger.fine('Getting file status for path: ${path.toString()}');
    try {
      final localPath = _toLocalPath(path);
      logger.finest('Checking entity type for local path: $localPath');
      final entity = FileSystemEntity.isDirectorySync(localPath)
          ? Directory(localPath)
          : File(localPath);

      if (!await entity.exists()) {
        logger.fine('Entity does not exist: ${path.toString()}');
        return null;
      }

      final stat = await entity.stat();
      final fileStatus = FileStatus(
        path: path,
        size: stat.type == FileSystemEntityType.file ? stat.size : null,
        isDirectory: stat.type == FileSystemEntityType.directory,
        mimeType: stat.type == FileSystemEntityType.file
            ? detectMimeType(path.filename ?? '')
            : null,
      );

      logger.fine(
        'File status retrieved - path: ${path.toString()}, '
        'isDir: ${fileStatus.isDirectory}, size: ${fileStatus.size}',
      );
      return fileStatus;
    } on FileSystemException {
      logger.warning(
        'FileSystemException occurred while getting status for: '
        '${path.toString()}',
      );
      rethrow;
    } on IOException catch (e) {
      logger.warning(
        'IOException occurred while getting status for: ${path.toString()}, '
        'error: $e',
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to get file status: ${e.toString()}',
        path: path,
      );
    }
  }

  Stream<FileStatus> nonRecursiveList(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    logger.fine('Starting non-recursive list for path: ${path.toString()}');
    final localPath = _toLocalPath(path);
    int itemCount = 0;

    await for (final entity in Directory(localPath).list()) {
      try {
        final stat = await entity.stat();
        final fileStatus = FileStatus(
          path: _toPath(entity.path),
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          isDirectory: stat.type == FileSystemEntityType.directory,
          mimeType: stat.type == FileSystemEntityType.file
              ? detectMimeType(p.basename(entity.path))
              : null,
        );
        itemCount++;
        logger.finest(
          'Listed item $itemCount: '
          '${fileStatus.path.toString()} '
          '(${fileStatus.isDirectory ? "dir" : "file"})',
        );
        yield fileStatus;
      } on IOException catch (e) {
        logger.warning('IOException while listing ${entity.path}: $e');
        continue; // 跳过IO错误的文件
      }
    }

    logger.fine(
      'Completed non-recursive list for ${path.toString()}, '
      'found $itemCount items',
    );
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    logger.fine(
      'Starting ${options.recursive ? "recursive" : "non-recursive"} '
      'list for path: ${path.toString()}',
    );
    // 遍历目录
    return listImplByNonRecursive(
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  Future<void> nonRecursiveCopyFile(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    logger.fine(
      'Copying file from ${source.toString()} to ${destination.toString()}',
    );
    return copyFileByReadAndWrite(
      source,
      destination,
      openWrite: openWrite,
      openRead: openRead,
    );
    // return File(_toLocalPath(source)).copy(_toLocalPath(destination));
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    logger.info(
      'Starting copy operation '
      'from ${source.toString()} to ${destination.toString()}',
    );
    try {
      await copyImplByNonRecursive(
        source: source,
        destination: destination,
        options: options,
        nonRecursiveCopyFile: nonRecursiveCopyFile,
        nonRecursiveList: nonRecursiveList,
        nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
      );
      logger.info(
        'Copy operation completed successfully '
        'from ${source.toString()} to ${destination.toString()}',
      );
    } catch (e) {
      logger.warning(
        'Copy operation failed '
        'from ${source.toString()} to ${destination.toString()}: $e',
      );
      rethrow;
    }
  }

  Future<void> nonRecursiveCreateDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    logger.fine('Creating directory: ${path.toString()}');
    try {
      final localPath = _toLocalPath(path);
      final directory = Directory(localPath);

      // 检查父目录是否存在
      final parent = directory.parent;
      if (!await parent.exists()) {
        logger.warning(
          'Parent directory does not exist for: ${path.toString()}',
        );
        throw FileSystemException.notFound(_toPath(parent.path));
      }

      // 创建目录
      await directory.create();
      logger.fine('Directory created successfully: ${path.toString()}');
    } on IOException catch (e) {
      logger.warning(
        'IOException while creating directory ${path.toString()}: $e',
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to create directory: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    logger.info('Starting create directory operation for: ${path.toString()}');
    return createDirectoryImplByNonRecursive(
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
      path: path,
      options: options,
    );
  }

  Future<void> nonRecursiveDelete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    logger.fine(
      'Deleting entity: ${path.toString()} (recursive: ${options.recursive})',
    );
    try {
      final localPath = _toLocalPath(path);
      final entity = FileSystemEntity.typeSync(localPath);

      switch (entity) {
        case FileSystemEntityType.file:
          logger.finest('Deleting file: ${path.toString()}');
          await File(localPath).delete();
          break;
        case FileSystemEntityType.directory:
          logger.finest(
            'Deleting directory: ${path.toString()} '
            '(recursive: ${options.recursive})',
          );
          await Directory(localPath).delete(recursive: options.recursive);
          break;
        case FileSystemEntityType.link:
          logger.finest('Deleting link: ${path.toString()}');
          await Link(localPath).delete();
          break;
        default:
          logger.warning(
            'Unsupported entity type for deletion: ${path.toString()}',
          );
          throw FileSystemException.unsupportedEntity(path);
      }
      logger.fine('Entity deleted successfully: ${path.toString()}');
    } on FileSystemException catch (e) {
      logger.warning(
        'FileSystemException while deleting ${path.toString()}: $e',
      );
      rethrow;
    } on IOException catch (e) {
      logger.warning('IOException while deleting ${path.toString()}: $e');
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to delete: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    logger.info(
      'Starting delete operation for: ${path.toString()} '
      '(recursive: ${options.recursive})',
    );
    return deleteImplByNonRecursive(
      nonRecursiveDelete: nonRecursiveDelete,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    logger.fine(
      'Opening write stream for: ${path.toString()} (mode: ${options.mode})',
    );
    await preOpenWriteCheck(path, options: options);
    try {
      final sink = File(_toLocalPath(path)).openWrite(
        mode: {
          WriteMode.write: FileMode.write,
          WriteMode.overwrite: FileMode.writeOnly,
          WriteMode.append: FileMode.append,
        }[options.mode]!,
      );
      logger.fine('Write stream opened successfully for: ${path.toString()}');
      return sink;
    } on IOException catch (e) {
      logger.warning(
        'IOException while opening write stream for ${path.toString()}: $e',
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to open write stream: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    logger.fine(
      'Opening read stream for: ${path.toString()} '
      '(start: ${options.start}, end: ${options.end})',
    );
    await preOpenReadCheck(path, options: options);
    try {
      int bytesRead = 0;
      // 打开文件并读取内容
      await for (final chunk in File(
        _toLocalPath(path),
      ).openRead(options.start, options.end)) {
        bytesRead += chunk.length;
        logger.finest(
          'Read chunk of ${chunk.length} bytes from ${path.toString()}',
        );
        yield chunk; // 逐块返回文件内容
      }
      logger.fine(
        'Read stream completed for ${path.toString()}, total bytes: $bytesRead',
      );
    } on IOException catch (e) {
      logger.warning('IOException while reading file ${path.toString()}: $e');
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to read file: ${e.toString()}',
        path: path,
      );
    }
  }
}
