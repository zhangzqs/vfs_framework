import 'dart:async';
import 'dart:typed_data';
import 'package:vfs_framework/src/abstract/context.dart';

import 'path.dart';
import 'status.dart';

enum WriteMode {
  // 正常写，如果文件不存在则创建，存在则报错
  write,
  // 覆盖写，如果文件不存在则创建，存在则覆盖
  overwrite,
  // 追加写，如果文件不存在则创建，存在则在末尾追加内容
  append,
}

final class WriteOptions {
  const WriteOptions({this.mode = WriteMode.write});

  final WriteMode mode;
}

final class ReadOptions {
  const ReadOptions({this.start, this.end});
  final int? start;
  final int? end;
}

final class StatOptions {
  const StatOptions();
}

final class ListOptions {
  const ListOptions({this.recursive = false});
  final bool recursive;
}

final class CopyOptions {
  const CopyOptions({this.overwrite = false, this.recursive = false});
  final bool overwrite;
  final bool recursive;
}

final class DeleteOptions {
  const DeleteOptions({this.recursive = false});
  final bool recursive;
}

final class CreateDirectoryOptions {
  const CreateDirectoryOptions({this.createParents = false});
  final bool createParents;
}

final class MoveOptions {
  const MoveOptions({this.overwrite = false, this.recursive = false});
  final bool overwrite;
  final bool recursive;
}

final class ExistsOptions {
  const ExistsOptions();
}

abstract class IFileSystem {
  /// 写入
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  });

  /// 读取部分文件内容
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  });

  /// 获取文件属性
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  });

  /// 列举文件内容
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  });

  /// 拷贝文件/目录
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  });

  /// 删除文件/目录
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  });

  /// 创建目录
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  });

  /// 移动文件/目录
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  });

  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  });
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  });
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  });
}
