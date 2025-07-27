import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

void main() {
  group('test BlockCacheFileSystem by filesystem test suites', () {
    late BlockCacheFileSystem blockCacheFs;

    setUp(() async {
      final baseFs = MemoryFileSystem();
      final cacheFs = MemoryFileSystem();

      blockCacheFs = BlockCacheFileSystem(
        originFileSystem: baseFs,
        cacheFileSystem: cacheFs,
        cacheDir: Path.rootPath,
        blockSize: Random.secure().nextInt(10) + 1, // 设置块大小为[1,10]字节
      );
    });

    testFilesystem(() => blockCacheFs);

    group('some test', () {
      test('should check file existence correctly', () async {
        // 在base上写入，在blockCache上检查
        await blockCacheFs.writeBytes(
          Path.fromString('/file1.txt'),
          Uint8List.fromList('Content in file1.txt'.codeUnits),
        );
        expect(
          await blockCacheFs.exists(Path.fromString('/file1.txt')),
          isTrue,
        );
        expect(
          await blockCacheFs.exists(Path.fromString('/nonexistent.txt')),
          isFalse,
        );
        // 读取文件内容
        final bytes = await blockCacheFs.readAsBytes(
          Path.fromString('/file1.txt'),
        );
        expect(String.fromCharCodes(bytes), 'Content in file1.txt');
      });
    });
  });
}
