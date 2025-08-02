import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

void main() {
  group('test MemoryFileSystem by filesystem test suites', () {
    late MemoryFileSystem fileSystem;
    setUp(() {
      // 使用内存文件系统
      fileSystem = MemoryFileSystem();
    });
    testFilesystem(() => fileSystem);

    group('test some', () {
      test('throws when listing a file instead of directory', () async {
        final context = Context();
        final fs = fileSystem;
        final filePath = Path.fromString('/test_file.txt');
        await fs.writeBytes(context, filePath, Uint8List.fromList([1, 2, 3]));
        expect(
          () => fs.list(context, filePath).toList(),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.code,
              'code',
              FileSystemErrorCode.notADirectory,
            ),
          ),
        );
      });
    });
  });
}
