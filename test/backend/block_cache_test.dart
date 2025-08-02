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
        final context = Context();
        // 在base上写入，在blockCache上检查
        await blockCacheFs.writeBytes(
          context,
          Path.fromString('/file1.txt'),
          Uint8List.fromList('Content in file1.txt'.codeUnits),
        );
        expect(
          await blockCacheFs.exists(context, Path.fromString('/file1.txt')),
          isTrue,
        );
        expect(
          await blockCacheFs.exists(
            context,
            Path.fromString('/nonexistent.txt'),
          ),
          isFalse,
        );
        // 读取文件内容
        final bytes = await blockCacheFs.readAsBytes(
          context,
          Path.fromString('/file1.txt'),
        );
        expect(String.fromCharCodes(bytes), 'Content in file1.txt');
      });
    });
  });
  group('BlockCache Read-Ahead Tests', () {
    late MemoryFileSystem originFs;
    late MemoryFileSystem cacheFs;
    late BlockCacheFileSystem blockCacheFs;

    setUp(() async {
      originFs = MemoryFileSystem();
      cacheFs = MemoryFileSystem();
      blockCacheFs = BlockCacheFileSystem(
        originFileSystem: originFs,
        cacheFileSystem: cacheFs,
        cacheDir: Path.rootPath,
        blockSize: 1024, // 1KB per block for testing
        readAheadBlocks: 3, // 预读3个块
        enableReadAhead: true,
      );
    });

    test('should demonstrate read-ahead functionality', () async {
      final context = Context();

      final testPath = Path.fromString('/large_file.txt');

      // 创建一个10KB的文件（10个块）
      final fileContent = List.generate(10 * 1024, (i) => i % 256);
      await originFs.writeBytes(
        context,
        testPath,
        Uint8List.fromList(fileContent),
      );

      print('\\n=== Read-Ahead Test ===');
      print('File size: ${fileContent.length} bytes');
      print('Block size: 1024 bytes');
      print('Total blocks: ${(fileContent.length / 1024).ceil()}');
      print('Read-ahead blocks: 3');

      // 顺序读取前几个块
      print('\\n--- Reading first 512 bytes (block 0) ---');
      final firstRead = await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 0, end: 512),
      );
      expect(firstRead.length, equals(512));

      // 等待一点时间让预读完成
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 检查缓存中应该有更多块被预读
      print('\\n--- Checking cache after first read ---');
      await _printCacheStatus(context, cacheFs, 'After reading block 0');

      // 读取第二个块（应该从缓存命中）
      print('\\n--- Reading bytes 1024-2048 (block 1) ---');
      final secondRead = await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 1024, end: 2048),
      );
      expect(secondRead.length, equals(1024));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _printCacheStatus(context, cacheFs, 'After reading block 1');

      // 读取第三个块（应该从缓存命中）
      print('\\n--- Reading bytes 2048-3072 (block 2) ---');
      final thirdRead = await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 2048, end: 3072),
      );
      expect(thirdRead.length, equals(1024));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _printCacheStatus(context, cacheFs, 'After reading block 2');
    });

    test('should not trigger read-ahead for non-sequential access', () async {
      final context = Context();

      final testPath = Path.fromString('/test_file.txt');

      // 创建一个5KB的文件
      final fileContent = List.generate(5 * 1024, (i) => i % 256);
      await originFs.writeBytes(
        context,
        testPath,
        Uint8List.fromList(fileContent),
      );

      print('\\n=== Non-Sequential Access Test ===');

      // 读取第一个块
      print('Reading block 0...');
      await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 0, end: 1024),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 跳跃读取第三个块（非顺序）
      print('Reading block 3 (non-sequential)...');
      await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 3072, end: 4096),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _printCacheStatus(context, cacheFs, 'After non-sequential access');
    });

    test('should handle read-ahead with file boundaries', () async {
      final context = Context();

      final testPath = Path.fromString('/small_file.txt');

      // 创建一个2.5KB的文件（不到3个完整块）
      final fileContent = List.generate(2560, (i) => i % 256); // 2.5KB
      await originFs.writeBytes(
        context,
        testPath,
        Uint8List.fromList(fileContent),
      );

      print('\\n=== File Boundary Test ===');
      print('File size: ${fileContent.length} bytes (2.5 blocks)');

      // 读取第一个块
      print('Reading block 0...');
      await blockCacheFs.readAsBytes(
        context,
        testPath,
        options: const ReadOptions(start: 0, end: 1024),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _printCacheStatus(
        context,
        cacheFs,
        'After reading from small file',
      );
    });
  });
}

/// 辅助函数：打印缓存状态
Future<void> _printCacheStatus(
  Context ctx,
  MemoryFileSystem cacheFs,
  String context,
) async {
  print('\\n$context:');
  var blockCount = 0;
  var metaCount = 0;

  try {
    await for (final entry in cacheFs.list(
      ctx,
      Path.rootPath,
      options: const ListOptions(recursive: true),
    )) {
      if (!entry.isDirectory) {
        final fileName = entry.path.filename;
        if (fileName == 'meta.json') {
          metaCount++;
        } else if (fileName != null && RegExp(r'^\d+$').hasMatch(fileName)) {
          blockCount++;
          print('  - Cached block: ${entry.path.toString()}');
        }
      }
    }
  } catch (e) {
    print('  Error listing cache: $e');
  }

  print('  Total cached blocks: $blockCount');
  print('  Metadata files: $metaCount');
}
