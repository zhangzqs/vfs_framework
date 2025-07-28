import 'dart:async';

import 'package:logging/logging.dart';
import 'package:vfs_framework/src/abstract/index.dart';
import 'package:vfs_framework/src/helper/filesystem_helper.dart';

class WebDavFileSystem extends IFileSystem with FileSystemHelper {
  WebDavFileSystem() : logger = Logger('WebDavFileSystem');

  @override
  final Logger logger;

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    // TODO: implement copy
    throw UnimplementedError();
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    // TODO: implement createDirectory
    throw UnimplementedError();
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    // TODO: implement list
    throw UnimplementedError();
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // TODO: implement openRead
    throw UnimplementedError();
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) {
    // TODO: implement openWrite
    throw UnimplementedError();
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) {
    // TODO: implement stat
    throw UnimplementedError();
  }
}
