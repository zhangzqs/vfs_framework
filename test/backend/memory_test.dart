import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

void main() {
  group("test MemoryFileSystem by filesystem test suites", () {
    late MemoryFileSystem fileSystem;
    setUp(() {
      // 使用内存文件系统
      fileSystem = MemoryFileSystem();
    });
    testFilesystem(() => fileSystem);
  });
}
