import 'dart:io';

import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

void main() {
  group('test LocalFileSystem by filesystem test suites', () {
    late LocalFileSystem fileSystem;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('filesystem_test_');
      // 使用临时目录作为基础目录创建文件系统
      fileSystem = LocalFileSystem(baseDir: tempDir);
    });
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testFilesystem(() => fileSystem);
  });
}
