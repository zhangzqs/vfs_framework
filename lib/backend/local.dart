import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vfs_framework/core/index.dart';
import 'package:vfs_framework/helper/filesystem_helper.dart';

class LocalFileSystem extends IFileSystem with FileSystemHelper {
  /// 本地文件系统的基础目录
  final String baseDir;
  LocalFileSystem({String? baseDir})
    : baseDir = p.normalize(p.absolute(baseDir ?? Directory.current.path));

  // 将抽象Path转换为本地文件系统路径
  String _toLocalPath(Path path) {
    // 使用path包处理跨平台路径拼接
    return p.join(baseDir, p.joinAll(path.segments));
  }

  // 将本地路径转换为抽象Path
  Path _toPath(String localPath) {
    // 计算相对于baseDir的相对路径
    String relative = p.relative(localPath, from: baseDir);

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

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final localPath = _toLocalPath(path);

    // 检查路径是否存在（不区分文件或目录）
    if (!await FileSystemEntity.isFile(localPath) &&
        !await FileSystemEntity.isDirectory(localPath)) {
      throw FileSystemException.notFound(path);
    }

    // 检查是否是目录
    if (!await FileSystemEntity.isDirectory(localPath)) {
      throw FileSystemException.notADirectory(path);
    }

    final directory = Directory(localPath);
    // 遍历目录
    await for (final entity in directory.list()) {
      try {
        final stat = await entity.stat();
        yield FileStatus(
          path: _toPath(entity.path),
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          isDirectory: stat.type == FileSystemEntityType.directory,
        );
      } on FileSystemException {
        continue; // 跳过无法访问的文件
      } on IOException {
        continue; // 跳过IO错误的文件
      }
    }
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    // 检查源是否存在
    final srcStat = await stat(source);
    if (srcStat == null) {
      throw FileSystemException.notFound(source);
    }
    // 检查目标是否已存在
    final destStat = await stat(destination);
    if (destStat == null) {
      if (srcStat.isDirectory) {
        // 源是目录，目标不存在
      } else {
        // 源是文件，目标不存在
      }
    } else {
      if (srcStat.isDirectory) {
        
      } else {
        
      }
    }

    try {
      final sourcePath = _toLocalPath(source);
      final destPath = _toLocalPath(destination);

      // 如果是文件，直接复制
      if (await FileSystemEntity.isFile(sourcePath)) {
        await File(sourcePath).copy(destPath);
      }
      // 如果是目录，递归复制
      else if (await FileSystemEntity.isDirectory(sourcePath)) {
        throw UnimplementedError("Directory copy not implemented yet");
        // await Directory(sourcePath).copy(destPath);
      }
      // 其他类型（如链接）
      else {
        throw FileSystemException.unsupportedEntity(source);
      }
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to copy: ${e.toString()}',
        path: source,
      );
    }
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    // 如果要创建的目录已存在，则报错
    if (await exists(path)) {
      throw FileSystemException.alreadyExists(path);
    }
    try {
      final localPath = _toLocalPath(path);
      final directory = Directory(localPath);

      if (options.recursive) {
        await directory.create(recursive: true);
      } else {
        // 检查父目录是否存在
        final parent = directory.parent;
        if (!await parent.exists()) {
          throw FileSystemException.notFound(_toPath(parent.path));
        }
        await directory.create();
      }
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to create directory: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    // 如果目标路径找不到则报错
    if (!await exists(path)) {
      throw FileSystemException.notFound(path);
    }
    // 如果是目录且不允许递归删除且目录不为空，则报错
    if (await FileSystemEntity.isDirectory(_toLocalPath(path)) &&
        !options.recursive &&
        !await Directory(_toLocalPath(path)).list().isEmpty) {
      throw FileSystemException.notEmptyDirectory(path);
    }
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
      }
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
      // 处理目录非空错误
      if (e.toString().contains('Directory not empty')) {
        throw FileSystemException.notEmptyDirectory(path);
      }
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to delete: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    try {
      final localPath = _toLocalPath(path);
      final file = File(localPath);

      // 检查文件是否已存在且不允许覆盖
      if (await file.exists() && !options.overwrite && !options.append) {
        throw FileSystemException.alreadyExists(path);
      }

      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      return file.openWrite(
        mode: options.append ? FileMode.append : FileMode.write,
      );
    } on FileSystemException {
      rethrow;
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
    try {
      final localPath = _toLocalPath(path);

      // 检查路径是否存在（不区分文件或目录）
      if (!await FileSystemEntity.isFile(localPath) &&
          !await FileSystemEntity.isDirectory(localPath)) {
        throw FileSystemException.notFound(path);
      }

      // 检查是否是文件（不是目录）
      if (!await FileSystemEntity.isFile(localPath)) {
        throw FileSystemException.notAFile(path);
      }

      final file = File(localPath);
      // 打开文件并读取内容
      await for (final chunk in file.openRead(options.start, options.end)) {
        yield chunk; // 逐块返回文件内容
      }
    } on FileSystemException {
      rethrow;
    } on IOException catch (e) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to read file: ${e.toString()}',
        path: path,
      );
    }
  }
}
