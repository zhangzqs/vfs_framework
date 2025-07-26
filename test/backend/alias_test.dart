import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';
import 'dart:typed_data';

void main() {
  group('AliasFileSystem', () {
    late MemoryFileSystem baseFs;
    late AliasFileSystem aliasFs;

    setUp(() async {
      baseFs = MemoryFileSystem();
      
      // 创建基础文件系统结构
      await baseFs.createDirectory(Path.fromString('/base'));
      await baseFs.createDirectory(Path.fromString('/base/subdir'));
      await baseFs.writeBytes(
        Path.fromString('/base/file1.txt'),
        Uint8List.fromList('Content in base/file1.txt'.codeUnits),
      );
      await baseFs.writeBytes(
        Path.fromString('/base/subdir/file2.txt'),
        Uint8List.fromList('Content in base/subdir/file2.txt'.codeUnits),
      );
      await baseFs.writeBytes(
        Path.fromString('/root_file.txt'),
        Uint8List.fromList('Root file content'.codeUnits),
      );
      
      // 创建alias文件系统，指向/base目录
      aliasFs = AliasFileSystem(
        fileSystem: baseFs,
        subDirectory: Path.fromString('/base'),
      );
    });

    test('should check file existence correctly', () async {
      // 通过alias访问应该能找到base目录下的文件
      expect(await aliasFs.exists(Path.fromString('/file1.txt')), isTrue);
      expect(await aliasFs.exists(Path.fromString('/subdir/file2.txt')), isTrue);
      expect(await aliasFs.exists(Path.fromString('/nonexistent.txt')), isFalse);
      
      // 不应该能访问base目录外的文件
      expect(await aliasFs.exists(Path.fromString('/root_file.txt')), isFalse);
    });

    test('should read files correctly', () async {
      final content1 = await aliasFs.readAsBytes(Path.fromString('/file1.txt'));
      expect(String.fromCharCodes(content1), equals('Content in base/file1.txt'));
      
      final content2 = await aliasFs.readAsBytes(Path.fromString('/subdir/file2.txt'));
      expect(String.fromCharCodes(content2), equals('Content in base/subdir/file2.txt'));
    });

    test('should write files correctly', () async {
      await aliasFs.writeBytes(
        Path.fromString('/new_file.txt'),
        Uint8List.fromList('New file content'.codeUnits),
      );
      
      // 验证文件被写入到正确的位置
      expect(await baseFs.exists(Path.fromString('/base/new_file.txt')), isTrue);
      
      final content = await baseFs.readAsBytes(Path.fromString('/base/new_file.txt'));
      expect(String.fromCharCodes(content), equals('New file content'));
    });

    test('should list directory contents correctly', () async {
      final files = <String>[];
      await for (final status in aliasFs.list(Path.rootPath)) {
        files.add(status.path.toString());
      }
      
      expect(files, contains('/file1.txt'));
      expect(files, contains('/subdir'));
      expect(files, hasLength(2)); // 只有base目录下的内容
    });

    test('should create directories correctly', () async {
      await aliasFs.createDirectory(Path.fromString('/new_dir'));
      
      // 验证目录被创建在正确的位置
      expect(await baseFs.exists(Path.fromString('/base/new_dir')), isTrue);
      
      final stat = await baseFs.stat(Path.fromString('/base/new_dir'));
      expect(stat?.isDirectory, isTrue);
    });

    test('should delete files and directories correctly', () async {
      await aliasFs.delete(Path.fromString('/file1.txt'));
      
      expect(await aliasFs.exists(Path.fromString('/file1.txt')), isFalse);
      expect(await baseFs.exists(Path.fromString('/base/file1.txt')), isFalse);
    });

    test('should copy files correctly', () async {
      await aliasFs.copy(
        Path.fromString('/file1.txt'),
        Path.fromString('/file1_copy.txt'),
      );
      
      expect(await aliasFs.exists(Path.fromString('/file1_copy.txt')), isTrue);
      
      final content = await aliasFs.readAsBytes(Path.fromString('/file1_copy.txt'));
      expect(String.fromCharCodes(content), equals('Content in base/file1.txt'));
    });

    test('should move files correctly', () async {
      await aliasFs.move(
        Path.fromString('/file1.txt'),
        Path.fromString('/moved_file.txt'),
      );
      
      expect(await aliasFs.exists(Path.fromString('/file1.txt')), isFalse);
      expect(await aliasFs.exists(Path.fromString('/moved_file.txt')), isTrue);
      
      final content = await aliasFs.readAsBytes(Path.fromString('/moved_file.txt'));
      expect(String.fromCharCodes(content), equals('Content in base/file1.txt'));
    });

    test('should handle root alias correctly', () async {
      // 测试指向根目录的alias
      final rootAliasFs = AliasFileSystem(fileSystem: baseFs);
      
      expect(await rootAliasFs.exists(Path.fromString('/root_file.txt')), isTrue);
      expect(await rootAliasFs.exists(Path.fromString('/base/file1.txt')), isTrue);
      
      final content = await rootAliasFs.readAsBytes(Path.fromString('/root_file.txt'));
      expect(String.fromCharCodes(content), equals('Root file content'));
    });

    test('should handle nested subdirectory correctly', () async {
      // 测试指向更深层子目录的alias
      final nestedAliasFs = AliasFileSystem(
        fileSystem: baseFs,
        subDirectory: Path.fromString('/base/subdir'),
      );
      
      expect(await nestedAliasFs.exists(Path.fromString('/file2.txt')), isTrue);
      expect(await nestedAliasFs.exists(Path.fromString('/file1.txt')), isFalse);
      
      final content = await nestedAliasFs.readAsBytes(Path.fromString('/file2.txt'));
      expect(String.fromCharCodes(content), equals('Content in base/subdir/file2.txt'));
    });

    test('should handle stat operations correctly', () async {
      final fileStat = await aliasFs.stat(Path.fromString('/file1.txt'));
      expect(fileStat, isNotNull);
      expect(fileStat!.isDirectory, isFalse);
      expect(fileStat.path.toString(), equals('/file1.txt'));
      
      final dirStat = await aliasFs.stat(Path.fromString('/subdir'));
      expect(dirStat, isNotNull);
      expect(dirStat!.isDirectory, isTrue);
      expect(dirStat.path.toString(), equals('/subdir'));
      
      final nonExistentStat = await aliasFs.stat(Path.fromString('/nonexistent'));
      expect(nonExistentStat, isNull);
    });

    test('should handle recursive directory listing', () async {
      final files = <String>[];
      await for (final status in aliasFs.list(
        Path.rootPath,
        options: const ListOptions(recursive: true),
      )) {
        files.add(status.path.toString());
      }
      
      expect(files, contains('/file1.txt'));
      expect(files, contains('/subdir'));
      expect(files, contains('/subdir/file2.txt'));
    });
  });
}
