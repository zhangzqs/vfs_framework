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
        UnionFileSystemItem(fileSystem: memoryFs1, mountPath: Path.rootPath),
        UnionFileSystemItem(
          fileSystem: memoryFs2,
          mountPath: Path.fromString('/fs2'),
        ),
      ]);
    });

    test('should check file existence correctly', () async {
      expect(await unionFs.exists(Path.fromString('/file1.txt')), isTrue);
      expect(await unionFs.exists(Path.fromString('/fs2/file2.txt')), isTrue);
      expect(
        await unionFs.exists(Path.fromString('/nonexistent.txt')),
        isFalse,
      );
    });

    test('should read files from correct filesystem', () async {
      final content1 = await unionFs.readAsBytes(Path.fromString('/file1.txt'));
      expect(String.fromCharCodes(content1), equals('Hello from filesystem 1'));

      final content2 = await unionFs.readAsBytes(
        Path.fromString('/fs2/file2.txt'),
      );
      expect(String.fromCharCodes(content2), equals('Hello from filesystem 2'));
    });

    test('should write to first writable filesystem', () async {
      await unionFs.writeBytes(
        Path.fromString('/new_file.txt'),
        Uint8List.fromList('New file content'.codeUnits),
      );

      // 应该写入到第一个文件系统
      expect(await memoryFs1.exists(Path.fromString('/new_file.txt')), isTrue);
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

    test('should handle priority and file override correctly', () async {
      final systemFs = MemoryFileSystem();
      final userFs = MemoryFileSystem();

      // 系统和用户都有同名文件
      await systemFs.writeBytes(
        Path.fromString('/config.ini'),
        Uint8List.fromList('system_config=default'.codeUnits),
      );
      await userFs.writeBytes(
        Path.fromString('/config.ini'),
        Uint8List.fromList('user_setting=custom'.codeUnits),
      );

      // 用户文件系统有更高优先级
      final priorityUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: userFs,
          mountPath: Path.rootPath,
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: systemFs,
          mountPath: Path.rootPath,
          priority: 50,
        ),
      ]);

      // 用户文件应该覆盖系统文件
      final content = await priorityUnionFs.readAsBytes(
        Path.fromString('/config.ini'),
      );
      expect(String.fromCharCodes(content), equals('user_setting=custom'));
    });

    test('should handle mount path specificity correctly', () async {
      final rootFs = MemoryFileSystem();
      final tmpFs = MemoryFileSystem();

      // 在临时文件系统中创建文件
      await tmpFs.writeBytes(
        Path.fromString('/session.dat'),
        Uint8List.fromList('temp session data'.codeUnits),
      );

      final mountUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: rootFs,
          mountPath: Path.rootPath,
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: tmpFs,
          mountPath: Path.fromString('/tmp'),
          priority: 50,
        ),
      ]);

      // 读取挂载点的文件
      final content = await mountUnionFs.readAsBytes(
        Path.fromString('/tmp/session.dat'),
      );
      expect(String.fromCharCodes(content), equals('temp session data'));

      // 写入到挂载点应该选择最具体的文件系统（tmpFs）
      await mountUnionFs.writeBytes(
        Path.fromString('/tmp/new_session.txt'),
        Uint8List.fromList('new session'.codeUnits),
      );

      // 验证文件被写入到临时文件系统
      expect(await tmpFs.exists(Path.fromString('/new_session.txt')), isTrue);
      expect(
        await rootFs.exists(Path.fromString('/tmp/new_session.txt')),
        isFalse,
      );
    });

    test('should handle cross-filesystem copy operations', () async {
      final sourceFs = MemoryFileSystem();
      final destFs = MemoryFileSystem();

      // 在源文件系统中创建文件
      await sourceFs.writeBytes(
        Path.fromString('/source.txt'),
        Uint8List.fromList('source content'.codeUnits),
      );

      final copyUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: sourceFs,
          mountPath: Path.fromString('/src'),
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: destFs,
          mountPath: Path.fromString('/dest'),
          priority: 50,
        ),
      ]);

      // 跨文件系统拷贝
      await copyUnionFs.copy(
        Path.fromString('/src/source.txt'),
        Path.fromString('/dest/copied.txt'),
      );

      // 验证拷贝成功
      expect(
        await copyUnionFs.exists(Path.fromString('/dest/copied.txt')),
        isTrue,
      );

      final copiedContent = await copyUnionFs.readAsBytes(
        Path.fromString('/dest/copied.txt'),
      );
      expect(String.fromCharCodes(copiedContent), equals('source content'));

      // 验证原文件仍然存在
      expect(
        await copyUnionFs.exists(Path.fromString('/src/source.txt')),
        isTrue,
      );
    });

    test('should handle cross-filesystem move operations', () async {
      final sourceFs = MemoryFileSystem();
      final destFs = MemoryFileSystem();

      // 在源文件系统中创建文件
      await sourceFs.writeBytes(
        Path.fromString('/moveme.txt'),
        Uint8List.fromList('move content'.codeUnits),
      );

      final moveUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: sourceFs,
          mountPath: Path.fromString('/src'),
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: destFs,
          mountPath: Path.fromString('/dest'),
          priority: 50,
        ),
      ]);

      // 跨文件系统移动
      await moveUnionFs.move(
        Path.fromString('/src/moveme.txt'),
        Path.fromString('/dest/moved.txt'),
      );

      // 验证文件被移动
      expect(
        await moveUnionFs.exists(Path.fromString('/dest/moved.txt')),
        isTrue,
      );
      expect(
        await moveUnionFs.exists(Path.fromString('/src/moveme.txt')),
        isFalse,
      );

      final movedContent = await moveUnionFs.readAsBytes(
        Path.fromString('/dest/moved.txt'),
      );
      expect(String.fromCharCodes(movedContent), equals('move content'));
    });

    test('should handle directory operations correctly', () async {
      final fs1 = MemoryFileSystem();
      final fs2 = MemoryFileSystem();

      await fs1.createDirectory(Path.fromString('/shared'));
      await fs1.writeBytes(
        Path.fromString('/shared/file1.txt'),
        Uint8List.fromList('from fs1'.codeUnits),
      );

      await fs2.createDirectory(Path.fromString('/shared'));
      await fs2.writeBytes(
        Path.fromString('/shared/file2.txt'),
        Uint8List.fromList('from fs2'.codeUnits),
      );

      final dirUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: fs1,
          mountPath: Path.rootPath,
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: fs2,
          mountPath: Path.fromString('/fs2'),
          priority: 50,
        ),
      ]);

      // 列出目录内容应该合并来自不同文件系统的文件
      final sharedFiles = <String>[];
      await for (final status in dirUnionFs.list(Path.fromString('/shared'))) {
        sharedFiles.add(status.path.toString());
      }

      expect(sharedFiles, contains('/shared/file1.txt'));

      // 列出fs2挂载点下的目录
      final fs2Files = <String>[];
      await for (final status in dirUnionFs.list(
        Path.fromString('/fs2/shared'),
      )) {
        fs2Files.add(status.path.toString());
      }

      expect(fs2Files, contains('/fs2/shared/file2.txt'));
    });

    test('should handle overwrite operations correctly', () async {
      final fs = MemoryFileSystem();

      // 创建初始文件
      await fs.writeBytes(
        Path.fromString('/overwrite_test.txt'),
        Uint8List.fromList('original content'.codeUnits),
      );

      final overwriteUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: fs,
          mountPath: Path.rootPath,
          priority: 100,
        ),
      ]);

      // 覆盖写入
      await overwriteUnionFs.writeBytes(
        Path.fromString('/overwrite_test.txt'),
        Uint8List.fromList('new content'.codeUnits),
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      // 验证内容被覆盖
      final content = await overwriteUnionFs.readAsBytes(
        Path.fromString('/overwrite_test.txt'),
      );
      expect(String.fromCharCodes(content), equals('new content'));
    });

    test('should handle complex three-layer filesystem setup', () async {
      final systemFs = MemoryFileSystem();
      final userFs = MemoryFileSystem();
      final tempFs = MemoryFileSystem();

      // 设置类似Unix的文件系统结构
      await systemFs.writeBytes(
        Path.fromString('/system.conf'),
        Uint8List.fromList('system_config=true'.codeUnits),
      );
      await systemFs.createDirectory(Path.fromString('/bin'));

      await userFs.writeBytes(
        Path.fromString('/config.ini'),
        Uint8List.fromList('user_setting=custom'.codeUnits),
      );
      await userFs.createDirectory(Path.fromString('/documents'));

      await tempFs.writeBytes(
        Path.fromString('/cache.tmp'),
        Uint8List.fromList('temp cache'.codeUnits),
      );

      final complexUnionFs = UnionFileSystem([
        UnionFileSystemItem(
          fileSystem: userFs,
          mountPath: Path.rootPath,
          priority: 100,
        ),
        UnionFileSystemItem(
          fileSystem: systemFs,
          mountPath: Path.rootPath,
          priority: 50,
        ),
        UnionFileSystemItem(
          fileSystem: tempFs,
          mountPath: Path.fromString('/tmp'),
          priority: 10,
        ),
      ]);

      // 验证各层文件都可访问
      expect(
        await complexUnionFs.exists(Path.fromString('/config.ini')),
        isTrue,
      );
      expect(
        await complexUnionFs.exists(Path.fromString('/system.conf')),
        isTrue,
      );
      expect(
        await complexUnionFs.exists(Path.fromString('/tmp/cache.tmp')),
        isTrue,
      );

      // 验证目录列表包含所有挂载点
      final rootFiles = <String>[];
      await for (final status in complexUnionFs.list(Path.rootPath)) {
        rootFiles.add(status.path.toString());
      }

      expect(rootFiles, contains('/tmp'));
      expect(rootFiles, contains('/config.ini'));
      expect(rootFiles, contains('/system.conf'));
      expect(rootFiles, contains('/bin'));
      expect(rootFiles, contains('/documents'));
    });
  });
}
