import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

import 'filesystem_testsuites.dart';

void main() {
  late IFileSystem originFs;
  late IFileSystem cacheFs;
  late MetadataCacheFileSystem metadataCacheFs;

  setUp(() async {
    originFs = MemoryFileSystem();
    cacheFs = MemoryFileSystem();
    metadataCacheFs = MetadataCacheFileSystem(
      originFileSystem: originFs,
      cacheFileSystem: cacheFs,
      cacheDir: Path.rootPath,
      maxCacheAge: const Duration(minutes: 5),
      largeDirectoryThreshold: 10,
    );
  });
  group('test MetadataCacheFileSystem by filesystem test suites', () {
    testFilesystem(() => metadataCacheFs);
  });

  group('some test', () {
    test('should check file existence correctly', () async {
      // 在origin上写入，在cache上检查
      await originFs.writeBytes(
        Path.fromString('/file1.txt'),
        Uint8List.fromList('Content in file1.txt'.codeUnits),
      );
      expect(
        await metadataCacheFs.exists(Path.fromString('/file1.txt')),
        isTrue,
      );
      expect(
        await metadataCacheFs.exists(Path.fromString('/nonexistent.txt')),
        isFalse,
      );
      // 读取文件内容
      final bytes = await metadataCacheFs.readAsBytes(
        Path.fromString('/file1.txt'),
      );
      expect(String.fromCharCodes(bytes), 'Content in file1.txt');
    });
    test(
      'list directory should return correct entries',
      timeout: const Timeout(Duration(days: 1)),
      () async {
        await metadataCacheFs.createDirectory(Path.fromString('/dir1'));
        await metadataCacheFs.writeBytes(
          Path.fromString('/dir1/file2.txt'),
          Uint8List.fromList('Content in dir1/file2.txt'.codeUnits),
        );
        await metadataCacheFs.writeBytes(
          Path.fromString('/dir1/file3.txt'),
          Uint8List.fromList('Content in dir1/file3.txt'.codeUnits),
        );

        // 列出目录内容
        final entries = await metadataCacheFs
            .list(Path.fromString('/dir1'))
            .toList();
        expect(entries.length, 2);
        expect(entries[0].path.filename, 'file2.txt');
        expect(entries[1].path.filename, 'file3.txt');
      },
    );
    test('should recursively list directory', skip: true, () async {
      // 在origin上创建嵌套目录和文件
      await metadataCacheFs.createDirectory(Path.fromString('/dir2'));
      await metadataCacheFs.writeBytes(
        Path.fromString('/dir2/file3.txt'),
        Uint8List.fromList('Content in dir2/file3.txt'.codeUnits),
      );
      await metadataCacheFs.createDirectory(Path.fromString('/dir2/subdir'));
      await metadataCacheFs.writeBytes(
        Path.fromString('/dir2/subdir/file4.txt'),
        Uint8List.fromList('Content in dir2/subdir/file4.txt'.codeUnits),
      );

      // 列出目录内容
      final entries = await metadataCacheFs
          .list(
            Path.fromString('/dir2'),
            options: const ListOptions(recursive: true),
          )
          .toList();
      expect(
        entries.map((e) => e.path.filename).toList(),
        containsAll(['file3.txt', 'file4.txt', 'subdir']),
      );
    });
  });
}
