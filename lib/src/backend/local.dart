import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import '../helper/mime_type_helper.dart';

class LocalFileSystem extends IFileSystem with FileSystemHelper {
  LocalFileSystem({Directory? baseDir})
    : baseDir = baseDir ?? Directory.current,
      logger = Logger('LocalFileSystem');

  @override
  final Logger logger;

  /// 本地文件系统的基础目录
  final Directory baseDir;

  // 将抽象Path转换为本地文件系统路径
  String _toLocalPath(Path path) {
    // 使用path包处理跨平台路径拼接
    return p.join(baseDir.path, p.joinAll(path.segments));
  }

  // 将本地路径转换为抽象Path
  Path _toPath(String localPath) {
    // 计算相对于baseDir的相对路径
    String relative = p.relative(localPath, from: baseDir.path);

    // 处理特殊情况：根目录
    if (relative == '.') return Path([]);

    // 使用path包分割路径
    return Path(p.split(relative));
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    try {
      final localPath = _toLocalPath(path);
      final entity = FileSystemEntity.isDirectorySync(localPath)
          ? Directory(localPath)
          : File(localPath);

      if (!await entity.exists()) {
        return null;
      }

      final stat = await entity.stat();
      return FileStatus(
        path: path,
        size: stat.type == FileSystemEntityType.file ? stat.size : null,
        isDirectory: stat.type == FileSystemEntityType.directory,
        mimeType: stat.type == FileSystemEntityType.file
            ? detectMimeType(path.filename ?? '')
            : null,
      );
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
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
    await for (final entity in Directory(_toLocalPath(path)).list()) {
      try {
        final stat = await entity.stat();
        yield FileStatus(
          path: _toPath(entity.path),
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          isDirectory: stat.type == FileSystemEntityType.directory,
          mimeType: stat.type == FileSystemEntityType.file
              ? detectMimeType(p.basename(entity.path))
              : null,
        );
      } on IOException {
        continue; // 跳过IO错误的文件
      }
    }
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
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
    return copyImplByNonRecursive(
      source: source,
      destination: destination,
      options: options,
      nonRecursiveCopyFile: nonRecursiveCopyFile,
      nonRecursiveList: nonRecursiveList,
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
    );
  }

  Future<void> nonRecursiveCreateDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    try {
      final localPath = _toLocalPath(path);
      final directory = Directory(localPath);

      // 检查父目录是否存在
      final parent = directory.parent;
      if (!await parent.exists()) {
        throw FileSystemException.notFound(_toPath(parent.path));
      }

      // 创建目录
      await directory.create();
    } on IOException catch (e) {
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
    try {
      final localPath = _toLocalPath(path);
      final entity = FileSystemEntity.typeSync(localPath);

      switch (entity) {
        case FileSystemEntityType.file:
          await File(localPath).delete();
          break;
        case FileSystemEntityType.directory:
          await Directory(localPath).delete(recursive: options.recursive);
          break;
        case FileSystemEntityType.link:
          await Link(localPath).delete();
          break;
        default:
          throw FileSystemException.unsupportedEntity(path);
      }
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
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
    await preOpenWriteCheck(path, options: options);
    try {
      return File(_toLocalPath(path)).openWrite(
        mode: {
          WriteMode.write: FileMode.write,
          WriteMode.overwrite: FileMode.writeOnly,
          WriteMode.append: FileMode.append,
        }[options.mode]!,
      );
    } on IOException catch (e) {
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
    await preOpenReadCheck(path, options: options);
    try {
      // 打开文件并读取内容
      await for (final chunk in File(
        _toLocalPath(path),
      ).openRead(options.start, options.end)) {
        yield chunk; // 逐块返回文件内容
      }
    } on IOException catch (e) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to read file: ${e.toString()}',
        path: path,
      );
    }
  }
}
