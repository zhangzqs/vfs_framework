import 'dart:typed_data';

import '../core/index.dart';

mixin FileSystemHelper on IFileSystem {
  /// 检查是否存在
  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    final status = await stat(path);
    return status != null;
  }

  /// 读取全部文件内容
  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    return openRead(path, options: options).fold<Uint8List>(
      Uint8List(0),
      (previous, element) => Uint8List.fromList(previous + element),
    );
  }

  /// 覆盖写入全部文件内容
  @override
  Future<void> writeBytes(
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) {
    return openWrite(path, options: options).then((sink) {
      sink.add(data);
      return sink.close();
    });
  }

  /// 移动文件/目录
  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    await copy(source, destination);
    await delete(source);
  }
}
