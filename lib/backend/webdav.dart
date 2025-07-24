import 'dart:async';
import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:vfs_framework/abstract/index.dart';
import 'package:vfs_framework/helper/filesystem_helper.dart';

class WebDavFileSystem extends IFileSystem with FileSystemHelper {
  final webdav.Client client;
  WebDavFileSystem({required this.client});

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    return client.copy(
      source.toString(),
      destination.toString(),
      options.overwrite,
    );
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    if (options.recursive) {
      return client.mkdirAll(path.toString());
    } else {
      return client.mkdir(path.toString());
    }
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    await client.removeAll(path.toString());
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final list = await client.readDir(path.toString());
    for (final item in list) {
      yield FileStatus(
        isDirectory: item.isDir ?? false,
        path: item.path != null ? Path.fromString(item.path!) : null,
        size: item.size,
      );
    }
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    // 先保存到本地文件
    final tmpDir = await Directory.systemTemp.createTemp('filesystem_tmp');
    final savePath = '${tmpDir.path}/${path.filename!}';
    await client.read2File(path.toString(), savePath);
    final file = File(savePath);
    yield* file.openRead(options.start, options.end);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    // 先保存到本地文件
    final tmpDir = await Directory.systemTemp.createTemp('filesystem_tmp');
    final savePath = '${tmpDir.path}/${path.filename!}';
    final file = File(savePath);
    final result = file.openWrite();
    return result;
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    // 使用list实现stat
    return list(path).first.then((status) {
      if (status.path == null) {
        return null;
      }
      return status;
    });
  }
}
