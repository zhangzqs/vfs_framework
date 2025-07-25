import 'dart:async';
import 'dart:io';

import 'package:vfs_framework/src/abstract/index.dart';
import 'package:vfs_framework/src/helper/filesystem_helper.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class WebDavFileSystem extends IFileSystem with FileSystemHelper {
  WebDavFileSystem({required this.client});
  final webdav.Client client;

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
    if (options.createParents) {
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
  }) async* {}

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
      return status;
    });
  }
}
