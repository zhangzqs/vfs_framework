import 'dart:io';

import 'package:test/test.dart';
import 'package:vfs_framework/backend/index.dart';
import 'package:vfs_framework/backend/local.dart';

import 'filesystem_testsuites.dart';

void main() {
  group("test LocalFileSystem", () {
    late LocalFileSystem fileSystem;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('filesystem_test_');
      // 使用临时目录作为基础目录创建文件系统
      fileSystem = LocalFileSystem(baseDir: tempDir.path);
    });
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testFilesystem(() => fileSystem);
  });

  group("test MemoryFileSystem", () {
    final fileSystem = MemoryFileSystem();

    testFilesystem(() => fileSystem);
  });
}
