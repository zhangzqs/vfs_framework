import 'dart:async';

import 'dart:typed_data';

import 'package:vfs_framework/vfs_framework.dart';
import 'package:vfs_framework/src/helper/filesystem_helper.dart';

/// 用于把另一个文件系统里的某个子文件夹作为一个新文件系统
class AliasFileSystem extends IFileSystem with FileSystemHelper {
  final IFileSystem fileSystem;
  final Path subDirectory;

  AliasFileSystem({required this.fileSystem, Path? subDirectory})
    : subDirectory = subDirectory ?? Path.rootPath;

  /// 将alias路径转换为底层文件系统的实际路径
  Path _convertToRealPath(Path aliasPath) {
    if (subDirectory.isRoot) {
      return aliasPath;
    }
    // 将alias路径与子目录路径合并
    return Path([...subDirectory.segments, ...aliasPath.segments]);
  }

  /// 将底层文件系统的路径转换为alias路径
  Path _convertFromRealPath(Path realPath) {
    if (subDirectory.isRoot) {
      return realPath;
    }
    
    // 检查路径是否在子目录下
    if (realPath.segments.length < subDirectory.segments.length) {
      throw ArgumentError('Real path is not under subdirectory');
    }
    
    // 验证路径前缀匹配
    for (int i = 0; i < subDirectory.segments.length; i++) {
      if (realPath.segments[i] != subDirectory.segments[i]) {
        throw ArgumentError('Real path is not under subdirectory');
      }
    }
    
    // 移除子目录前缀
    return Path(realPath.segments.sublist(subDirectory.segments.length));
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    final realSource = _convertToRealPath(source);
    final realDestination = _convertToRealPath(destination);
    return fileSystem.copy(realSource, realDestination, options: options);
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.createDirectory(realPath, options: options);
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.delete(realPath, options: options);
  }

  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.exists(realPath, options: options);
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final realPath = _convertToRealPath(path);
    
    await for (final status in fileSystem.list(realPath, options: options)) {
      // 将真实路径转换为alias路径
      final aliasPath = _convertFromRealPath(status.path);
      
      yield FileStatus(
        path: aliasPath,
        isDirectory: status.isDirectory,
        size: status.size,
        mimeType: status.mimeType,
      );
    }
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) {
    final realSource = _convertToRealPath(source);
    final realDestination = _convertToRealPath(destination);
    return fileSystem.move(realSource, realDestination, options: options);
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.openRead(realPath, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.openWrite(realPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    final realPath = _convertToRealPath(path);
    return fileSystem.readAsBytes(realPath, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final realPath = _convertToRealPath(path);
    final realStatus = await fileSystem.stat(realPath, options: options);
    
    if (realStatus == null) {
      return null;
    }
    
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
    final realPath = _convertToRealPath(path);
    return fileSystem.writeBytes(realPath, data, options: options);
  }
}
