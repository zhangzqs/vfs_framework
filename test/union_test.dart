import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';
import 'dart:typed_data';

void main() {
  group('UnionFileSystem', () {
    late MemoryFileSystem memoryFs1;
    late MemoryFileSystem memoryFs2;
    late UnionFileSystem unionFs;

    setUp(() async {
      memoryFs1 = MemoryFileSystem();
      memoryFs2 = MemoryFileSystem();
      
      // 在第一个文件系统中创建文件
      await memoryFs1.writeBytes(
        Path.fromString('/file1.txt'),
        Uint8List.fromList('Hello from filesystem 1'.codeUnits),
      );
      await memoryFs1.createDirectory(Path.fromString('/dir1'));
      
      // 在第二个文件系统中创建文件
      await memoryFs2.writeBytes(
        Path.fromString('/file2.txt'),
        Uint8List.fromList('Hello from filesystem 2'.codeUnits),
      );
      
      // 创建union文件系统
      unionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: memoryFs1,
          mountPath: Path.rootPath,
          priority: 10,
        ),
        UnionFileSystemItem(
          fileSystem: memoryFs2,
          mountPath: Path.fromString('/fs2'),
          priority: 5,
        ),
      ]);
    });

    test('should check file existence correctly', () async {
      expect(await unionFs.exists(Path.fromString('/file1.txt')), isTrue);
      expect(await unionFs.exists(Path.fromString('/fs2/file2.txt')), isTrue);
      expect(await unionFs.exists(Path.fromString('/nonexistent.txt')), isFalse);
    });

    test('should read files from correct filesystem', () async {
      final content1 = await unionFs.readAsBytes(Path.fromString('/file1.txt'));
      expect(String.fromCharCodes(content1), equals('Hello from filesystem 1'));
      
      final content2 = await unionFs.readAsBytes(Path.fromString('/fs2/file2.txt'));
      expect(String.fromCharCodes(content2), equals('Hello from filesystem 2'));
    });

    test('should write to first writable filesystem', () async {
      await unionFs.writeBytes(
        Path.fromString('/new_file.txt'),
        Uint8List.fromList('New file content'.codeUnits),
      );
      
      // 应该写入到第一个文件系统（因为它有更高的优先级）
      expect(await memoryFs1.exists(Path.fromString('/new_file.txt')), isTrue);
      expect(await memoryFs2.exists(Path.fromString('/new_file.txt')), isFalse);
    });

    test('should list files from all filesystems', () async {
      final files = <String>[];
      await for (final status in unionFs.list(Path.rootPath)) {
        files.add(status.path.toString());
      }
      
      expect(files, contains('/file1.txt'));
      expect(files, contains('/dir1'));
      expect(files, contains('/fs2'));
    });

    test('should handle read-only filesystems', () async {
      final readOnlyUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: memoryFs1,
          mountPath: Path.rootPath,
          readOnly: true,
          priority: 10,
        ),
      ]);
      
      expect(
        () => readOnlyUnionFs.writeBytes(
          Path.fromString('/readonly_test.txt'),
          Uint8List.fromList('test'.codeUnits),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
