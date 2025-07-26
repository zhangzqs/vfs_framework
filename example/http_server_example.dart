import 'dart:io';
import 'package:vfs_framework/src/abstract/index.dart';
import 'package:vfs_framework/src/backend/index.dart';
import 'package:vfs_framework/src/frontend/http.dart';

Future<void> main() async {
  // 创建本地文件系统后端
  final fs1 = LocalFileSystem(baseDir: Directory("C:/"));
  final fs2 = LocalFileSystem(baseDir: Directory("D:/"));
  final fs3 = LocalFileSystem(baseDir: Directory("Z:/"));
  final fs = UnionFileSystem([
    UnionFileSystemItem(fileSystem: fs1, mountPath: Path.fromString('/C')),
    UnionFileSystemItem(fileSystem: fs2, mountPath: Path.fromString('/D')),
    UnionFileSystemItem(fileSystem: fs3, mountPath: Path.fromString('/Z')),
  ]);

  // 创建HTTP服务器前端
  final httpServer = HttpServer(fs);

  // 启动服务器在8080端口
  await httpServer.start('localhost', 28080);

  // 监听终止信号
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n正在停止服务器...');
    await httpServer.stop();
    exit(0);
  });

  // 保持程序运行
  await Future.delayed(Duration(days: 365));
}
