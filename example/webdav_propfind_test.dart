import 'dart:typed_data';
import 'package:vfs_framework/src/backend/memory.dart';
import 'package:vfs_framework/src/backend/union.dart';
import 'package:vfs_framework/src/frontend/webdav.dart';
import 'package:vfs_framework/src/abstract/path.dart';
import 'package:shelf/shelf.dart';

void main() async {
  // 创建测试文件系统
  final fs1 = MemoryFileSystem();
  final fs2 = MemoryFileSystem();

  // 在文件系统中创建一些测试文件
  await fs1.writeBytes(Path(['file1.txt']), Uint8List.fromList([1, 2, 3]));
  await fs1.writeBytes(
    Path(['subdir', 'file2.txt']),
    Uint8List.fromList([4, 5, 6]),
  );
  await fs2.writeBytes(Path(['config.json']), Uint8List.fromList([7, 8, 9]));

  // 创建Union文件系统，挂载到子目录
  final unionFs = UnionFileSystem(
    items: [
      UnionFileSystemItem(
        fileSystem: fs1,
        mountPath: Path(['data']), // 挂载到 /data
        priority: 1,
      ),
      UnionFileSystemItem(
        fileSystem: fs2,
        mountPath: Path(['config']), // 挂载到 /config
        priority: 2,
      ),
    ],
  );

  // 创建WebDAV服务器
  final webdavServer = WebDAVServer(unionFs);

  print('测试根目录stat:');
  final rootStat = await unionFs.stat(Path.rootPath);
  print('Root stat: $rootStat');

  print('\n测试根目录list:');
  await for (final item in unionFs.list(Path.rootPath)) {
    print(
      '  - ${item.path}: ${item.isDirectory ? "目录" : "文件"} (${item.size} bytes)',
    );
  }

  print('\n测试PROPFIND请求:');
  final request = Request(
    'PROPFIND',
    Uri.parse('http://localhost:8080/'),
    headers: {'depth': '1'},
  );

  final response = await webdavServer.handleRequest(request);
  print('PROPFIND响应状态: ${response.statusCode}');
  print('PROPFIND响应内容:');
  print(await response.readAsString());

  print('\n测试/data目录PROPFIND:');
  final dataRequest = Request(
    'PROPFIND',
    Uri.parse('http://localhost:8080/data'),
    headers: {'depth': '1'},
  );

  final dataResponse = await webdavServer.handleRequest(dataRequest);
  print('Data PROPFIND响应状态: ${dataResponse.statusCode}');
  print('Data PROPFIND响应内容:');
  print(await dataResponse.readAsString());
}
