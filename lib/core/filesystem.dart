import 'dart:async';
import 'dart:typed_data';

import 'path.dart';
import 'status.dart';

final class WriteOptions {
  final bool overwrite;
  final bool append;

  const WriteOptions({this.overwrite = true, this.append = false});
}

final class ReadOptions {
  final int? start;
  final int? end;

  const ReadOptions({this.start, this.end});
}

final class StatOptions {
  const StatOptions();
}

final class ListOptions {
  const ListOptions();
}

final class CopyOptions {
  const CopyOptions();
}

final class DeleteOptions {
  final bool recursive;

  const DeleteOptions({this.recursive = false});
}

final class CreateDirectoryOptions {
  final bool recursive;

  const CreateDirectoryOptions({this.recursive = false});
}

final class MoveOptions {
  const MoveOptions();
}

final class ExistsOptions {
  const ExistsOptions();
}

abstract class IFileSystem {
  /// 写入
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  });

  /// 读取部分文件内容
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  });

  /// 获取文件属性
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  });

  /// 列举文件内容
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  });

  /// 拷贝文件/目录
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  });

  /// 删除文件/目录
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  });

  /// 创建目录
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  });

  /// 移动文件/目录
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  });

  Future<void> writeBytes(
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  });
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  });
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  });
}
