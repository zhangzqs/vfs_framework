import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:vfs_framework/src/backend/webdav/auth.dart';
import 'package:vfs_framework/src/backend/webdav/webdav_dio.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

Future<void> clearFileSystem(IFileSystem fs) async {
  await for (final entry in fs.list(Path.rootPath)) {
    try {
      if (entry.isDirectory) {
        await fs.delete(
          entry.path,
          options: const DeleteOptions(recursive: true),
        );
      } else {
        await fs.delete(entry.path);
      }
    } on FileSystemException catch (e) {
      if (e.code == FileSystemErrorCode.notFound) {
        // 如果文件已被删除，忽略错误
        continue;
      }
      // 其他错误抛出
      rethrow;
    }
  }
}

void main() {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8091'));

  dio.interceptors.add(
    const WebDAVBasicAuthInterceptor(username: 'admin', password: 'test'),
  );
  // dio.interceptors.add(
  //   LogInterceptor(
  //     request: true,
  //     responseBody: true,
  //     requestBody: true,
  //     error: true,
  //     logPrint: (Object? object) {
  //       print('Dio Log: $object');
  //     },
  //   ),
  // );
  final fileSystem = WebDAVFileSystem(dio);

  group('test WebDAVFileSystem by filesystem test suites', () {
    tearDown(() async {
      await clearFileSystem(fileSystem);
    });

    testFilesystem(() => fileSystem, skipAppendWriteTest: true);
  });

  group('test some', () {
    tearDown(() async {
      await clearFileSystem(fileSystem);
    });

    test('should ping WebDAV server', () async {
      await fileSystem.ping();
    });

    test('should check file existence correctly', () async {
      final path = Path.fromString('/test_file.txt');
      await fileSystem.writeBytes(
        path,
        Uint8List.fromList('Hello World'.codeUnits),
      );
      expect(await fileSystem.exists(path), isTrue);
      expect(
        await fileSystem.exists(Path.fromString('/nonexistent.txt')),
        isFalse,
      );

      final content = await fileSystem.readAsBytes(path);
      expect(String.fromCharCodes(content), 'Hello World');
    });
  });
}
