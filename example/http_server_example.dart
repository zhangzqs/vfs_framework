import 'dart:io';
import 'package:vfs_framework/backend/local.dart';
import 'package:vfs_framework/frontend/http.dart';

Future<void> main() async {
  // 创建本地文件系统后端
  final fs = LocalFileSystem(baseDir: "C:/Users/i/Desktop/code/vfs_framework");
  
  // 创建HTTP服务器
  final httpServer = HttpServer(fs);
  
  // 启动服务器在8080端口
  await httpServer.start('localhost', 28080);
  
  print('HTTP文件服务器已启动!');
  print('访问 http://localhost:8080 查看文件列表');
  print('按 Ctrl+C 停止服务器');
  
  // 监听终止信号
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n正在停止服务器...');
    await httpServer.stop();
    exit(0);
  });
  
  // 保持程序运行
  await Future.delayed(Duration(days: 365));
}
