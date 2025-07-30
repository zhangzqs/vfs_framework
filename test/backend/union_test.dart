import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

void main() {
  group('test UnionFileSystem', () {
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
      unionFs = UnionFileSystem(
        items: [
          UnionFileSystemItem(fileSystem: memoryFs1, mountPath: Path.rootPath),
          UnionFileSystemItem(
            fileSystem: memoryFs2,
            mountPath: Path.fromString('/fs2'),
          ),
        ],
      );
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
      final readOnlyUnionFs = UnionFileSystem(
        items: [
          UnionFileSystemItem(
            fileSystem: memoryFs1,
            mountPath: Path.rootPath,
            readOnly: true,
          ),
        ],
      );

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
      final priorityUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

      final mountUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

      final copyUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

      final moveUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

      final dirUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

      final overwriteUnionFs = UnionFileSystem(
        items: [
          UnionFileSystemItem(
            fileSystem: fs,
            mountPath: Path.rootPath,
            priority: 100,
          ),
        ],
      );

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

      final complexUnionFs = UnionFileSystem(
        items: [
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
        ],
      );

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

  group('UnionFileSystem Root Directory Tests', () {
    test('root directory should exist when child mounts are present', () async {
      // 创建两个内存文件系统
      final fs1 = MemoryFileSystem();
      final fs2 = MemoryFileSystem();

      // 在fs1中创建一些测试文件
      await fs1.writeBytes(Path(['test1.txt']), Uint8List.fromList([1, 2, 3]));
      await fs2.writeBytes(Path(['test2.txt']), Uint8List.fromList([4, 5, 6]));

      // 创建Union文件系统，没有挂载到根目录的文件系统
      final unionFs = UnionFileSystem(
        items: [
          UnionFileSystemItem(
            fileSystem: fs1,
            mountPath: Path(['data']), // 挂载到 /data
            priority: 1,
          ),
          UnionFileSystemItem(
            fileSystem: fs2,
            mountPath: Path(['config']), // 挂载到 /config
            priority: 2,
          ),
        ],
      );

      // 测试根目录应该存在
      final rootExists = await unionFs.exists(Path.rootPath);
      expect(
        rootExists,
        isTrue,
        reason: 'Root directory should exist when child mounts are present',
      );

      // 测试根目录的stat应该返回目录状态
      final rootStat = await unionFs.stat(Path.rootPath);
      expect(
        rootStat,
        isNotNull,
        reason: 'Root directory stat should not be null',
      );
      expect(
        rootStat!.isDirectory,
        isTrue,
        reason: 'Root should be a directory',
      );
      expect(rootStat.path.isRoot, isTrue, reason: 'Root path should be root');
    });

    test(
      'root directory should not exist when no mounts are present',
      () async {
        // 创建空的Union文件系统
        final unionFs = UnionFileSystem(items: []);

        // 测试根目录不应该存在
        final rootExists = await unionFs.exists(Path.rootPath);
        expect(
          rootExists,
          isFalse,
          reason: 'Root directory should not exist when no mounts are present',
        );

        // 测试根目录的stat应该返回null
        final rootStat = await unionFs.stat(Path.rootPath);
        expect(
          rootStat,
          isNull,
          reason:
              'Root directory stat should be null when no mounts are present',
        );
      },
    );

    test(
      'root directory should use actual filesystem when mounted at root',
      () async {
        // 创建内存文件系统
        final rootFs = MemoryFileSystem();
        final childFs = MemoryFileSystem();

        // 在根文件系统中创建文件
        await rootFs.writeBytes(
          Path(['root_file.txt']),
          Uint8List.fromList([1, 2, 3]),
        );
        await childFs.writeBytes(
          Path(['child_file.txt']),
          Uint8List.fromList([4, 5, 6]),
        );

        // 创建Union文件系统，其中一个挂载到根目录
        final unionFs = UnionFileSystem(
          items: [
            UnionFileSystemItem(
              fileSystem: rootFs,
              mountPath: Path.rootPath, // 挂载到根目录
              priority: 1,
            ),
            UnionFileSystemItem(
              fileSystem: childFs,
              mountPath: Path(['data']), // 挂载到 /data
              priority: 2,
            ),
          ],
        );

        // 测试根目录应该存在
        final rootExists = await unionFs.exists(Path.rootPath);
        expect(rootExists, isTrue, reason: 'Root directory should exist');

        // 测试可以访问根文件系统中的文件
        final rootFileExists = await unionFs.exists(Path(['root_file.txt']));
        expect(
          rootFileExists,
          isTrue,
          reason: 'Root file should be accessible',
        );

        // 测试可以访问子挂载点中的文件
        final childFileExists = await unionFs.exists(
          Path(['data', 'child_file.txt']),
        );
        expect(
          childFileExists,
          isTrue,
          reason: 'Child file should be accessible through mount point',
        );
      },
    );

    test('root directory listing should show mount points', () async {
      // 创建两个内存文件系统
      final fs1 = MemoryFileSystem();
      final fs2 = MemoryFileSystem();

      // 创建Union文件系统
      final unionFs = UnionFileSystem(
        items: [
          UnionFileSystemItem(
            fileSystem: fs1,
            mountPath: Path(['data']),
            priority: 1,
          ),
          UnionFileSystemItem(
            fileSystem: fs2,
            mountPath: Path(['config']),
            priority: 2,
          ),
        ],
      );

      // 列出根目录内容
      final rootListing = await unionFs.list(Path.rootPath).toList();

      // 应该包含挂载点
      final mountPointNames = rootListing.map((f) => f.path.filename).toSet();
      expect(
        mountPointNames,
        contains('data'),
        reason: 'Root listing should contain data mount point',
      );
      expect(
        mountPointNames,
        contains('config'),
        reason: 'Root listing should contain config mount point',
      );

      // 挂载点应该显示为目录
      for (final file in rootListing) {
        expect(
          file.isDirectory,
          isTrue,
          reason: 'Mount points should appear as directories',
        );
      }
    });
  });
}
