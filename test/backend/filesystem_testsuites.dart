import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

void testFilesystem(
  IFileSystem Function() fsGetter, {
  bool skipAppendWriteTest = false, // 跳过追加写入测试
}) {
  group('stat', () {
    test('return null for non-existen path', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non/existent/path');
      final status = await fs.stat(context, path);
      expect(status, isNull);
    });
    test('returns file status for existing file', () async {
      final context = Context();
      final fs = fsGetter();

      final path = Path.fromString('/file.txt');
      await fs.writeBytes(context, path, Uint8List.fromList([1, 2, 3, 4]));
      final result = await fs.stat(context, path);

      expect(result, isNotNull);
      expect(result!.isDirectory, false);
      expect(result.size, equals(4));
    });
    test('returns directory status for existing directory', () async {
      final context = Context();
      final fs = fsGetter();

      final path = Path.fromString('/test');
      await fs.createDirectory(context, path);
      final result = await fs.stat(context, path);

      expect(result, isNotNull);
      expect(result!.isDirectory, true);
      expect(result.size, isNull);
    });

    test('return directory status for root path', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/');
      final result = await fs.stat(context, path);

      expect(result, isNotNull);
      expect(result!.isDirectory, true);
      expect(result.size, isNull);
    });
  });

  group('exists', () {
    test('returns false for non-existent path', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non/existent/path');
      final exists = await fs.exists(context, path);
      expect(exists, isFalse);
    });

    test('returns true for existing file', () async {
      final context = Context();
      final fs = fsGetter();

      final path = Path.fromString('/file.txt');
      await fs.writeBytes(context, path, Uint8List.fromList([1, 2, 3, 4]));
      final exists = await fs.exists(context, path);

      expect(exists, isTrue);
    });

    test('returns true for existing directory', () async {
      final context = Context();
      final fs = fsGetter();

      final path = Path.fromString('/test');
      await fs.createDirectory(context, path);
      final exists = await fs.exists(context, path);

      expect(exists, isTrue);
    });
  });

  group('createDirectory', () {
    test('create directory successfully', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test');
      await fs.createDirectory(context, path);
      final exists = await fs.exists(context, path);
      expect(exists, isTrue);
    });

    test('create nested directories', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test/nested/dir');
      await fs.createDirectory(
        context,
        path,
        options: const CreateDirectoryOptions(createParents: true),
      );
      final exists = await fs.exists(context, path);
      expect(exists, isTrue);
    });

    test('throws when parent does not exist and recursive is false', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non/existent/dir');

      // 期望异常为FileSystemException并且包含notFound错误码
      expect(
        () async => fs.createDirectory(context, path),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('throws when trying to create a file as a directory', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/file.txt');
      await fs.writeBytes(context, path, Uint8List.fromList([1, 2, 3, 4]));

      // 期望异常为FileSystemException并且包含notADirectory错误码
      expect(
        () async => fs.createDirectory(context, path),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.alreadyExists,
          ),
        ),
      );
    });

    test('throws when trying to create an existing directory', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test');
      await fs.createDirectory(context, path);

      // 期望异常为FileSystemException并且包含alreadyExists错误码
      expect(
        () async => fs.createDirectory(context, path),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.alreadyExists,
          ),
        ),
      );
    });
  });

  group('delete', () {
    test('deletes file successfully', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/file.txt');
      await fs.writeBytes(context, path, Uint8List.fromList([1, 2, 3, 4]));
      expect(await fs.exists(context, path), isTrue);

      await fs.delete(context, path);
      expect(await fs.exists(context, path), isFalse);
    });

    test('deletes empty directory successfully', () async {
      final context = Context();
      final fs = fsGetter();

      // 创建一个空目录
      final path = Path.fromString('/dir');
      await fs.createDirectory(context, path);

      // 确认是个空目录
      final statRes = (await fs.stat(context, path))!;
      expect(statRes, isNotNull);
      expect(statRes.isDirectory, isTrue);
      expect(statRes.size, isNull);
      expect(await fs.exists(context, path), isTrue);
      expect(await fs.list(context, path).isEmpty, isTrue);

      await fs.delete(context, path);
      expect(await fs.exists(context, path), isFalse);
    });

    test('deletes non-empty directory with recursive option', () async {
      final context = Context();
      final fs = fsGetter();

      // 创建一个非空目录
      final dirPath = Path.fromString('/test/dir');
      await fs.createDirectory(
        context,
        dirPath,
        options: const CreateDirectoryOptions(createParents: true),
      );
      final filePath = Path.fromString('/test/dir/file.txt');
      await fs.writeBytes(context, filePath, Uint8List.fromList([1, 2, 3, 4]));

      // 确认目录和文件存在
      expect(await fs.exists(context, dirPath), isTrue);
      expect(await fs.exists(context, filePath), isTrue);

      // 删除目录
      await fs.delete(
        context,
        dirPath,
        options: const DeleteOptions(recursive: true),
      );
      expect(await fs.exists(context, dirPath), isFalse);
      expect(await fs.exists(context, filePath), isFalse);
    });

    test('throws when deleting non-existent path', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non/existent/path');

      expect(
        () => fs.delete(context, path),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test(
      'throws when deleting non-empty directory without recursive',
      () async {
        final context = Context();
        final fs = fsGetter();
        final dirPath = Path.fromString('/test/dir');
        final filePath = Path.fromString('/test/dir/file.txt');

        await fs.createDirectory(
          context,
          dirPath,
          options: const CreateDirectoryOptions(createParents: true),
        );
        await fs.writeBytes(
          context,
          filePath,
          Uint8List.fromList([1, 2, 3, 4]),
        );

        expect(
          () => fs.delete(context, dirPath),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.code,
              'code',
              FileSystemErrorCode.notEmptyDirectory,
            ),
          ),
        );
      },
    );
  });

  group('writeBytes and readAsBytes', () {
    test('writes and reads file content', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      await fs.writeBytes(context, path, data);
      final readData = await fs.readAsBytes(context, path);
      expect(readData, equals(data));
    });

    test('throws when writing existing file without overwrite', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      await fs.writeBytes(context, path, data);

      // 尝试写入同一文件，期望抛出异常
      expect(
        () => fs.writeBytes(context, path, data),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.alreadyExists,
          ),
        ),
      );

      // 尝试写入同一文件，允许覆盖
      final newData = Uint8List.fromList([6, 7, 8, 9, 10]);
      await fs.writeBytes(
        context,
        path,
        newData,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );
      final readData = await fs.readAsBytes(context, path);
      expect(readData, equals(newData));
    });

    test(
      'appends to existing file when append is true',
      skip: skipAppendWriteTest,
      () async {
        final context = Context();
        final fs = fsGetter();
        final path = Path.fromString('/test_file.txt');
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);

        await fs.writeBytes(context, path, data1);
        await fs.writeBytes(
          context,
          path,
          data2,
          options: const WriteOptions(mode: WriteMode.append),
        );

        final readData = await fs.readAsBytes(context, path);
        expect(readData, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
      },
    );
  });

  group('list files', () {
    test('lists files in directory', () async {
      final context = Context();
      final fs = fsGetter();
      final dirPath = Path.fromString('/test_dir');
      await fs.createDirectory(context, dirPath);

      final file1 = Path.fromString('/test_dir/file1.txt');
      final file2 = Path.fromString('/test_dir/file2.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));
      await fs.writeBytes(context, file2, Uint8List.fromList([4, 5, 6]));

      final files = await fs.list(context, dirPath).toList();
      expect(files.length, equals(2));
      expect(files.map((f) => f.path), containsAll([file1, file2]));
    });

    test('returns empty list for empty directory', () async {
      final context = Context();
      final fs = fsGetter();
      final dirPath = Path.fromString('/empty_dir');
      await fs.createDirectory(context, dirPath);

      final files = await fs.list(context, dirPath).toList();
      expect(files, isEmpty);
    });

    test('throws when listing non-existent directory', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non/existent/dir');

      expect(
        () => fs.list(context, path).toList(),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('throws when listing a file instead of directory', () async {
      final context = Context();
      final fs = fsGetter();
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

    test('lists files recursively', () async {
      final context = Context();
      final fs = fsGetter();
      final rootDir = Path.fromString('/root');
      await fs.createDirectory(context, rootDir);

      final subDir = Path.fromString('/root/sub');
      await fs.createDirectory(context, subDir);

      final file1 = Path.fromString('/root/file1.txt');
      final file2 = Path.fromString('/root/sub/file2.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));
      await fs.writeBytes(context, file2, Uint8List.fromList([4, 5, 6]));

      final files = await fs
          .list(context, rootDir, options: const ListOptions(recursive: true))
          .toList();

      expect(files.length, equals(3));
      expect(files.map((f) => f.path), containsAll([file1, file2, subDir]));
      expect(files.map((f) => f.path).toSet(), equals({file1, subDir, file2}));
    });
  });

  group('copy', () {
    test('copy src not found', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/non/existent/file.txt');
      final destPath = Path.fromString('/dest/file.txt');

      expect(
        () => fs.copy(context, sourcePath, destPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('copies file successfully', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/source.txt');
      final destPath = Path.fromString('/dest.txt');
      await fs.writeBytes(
        context,
        sourcePath,
        Uint8List.fromList([1, 2, 3, 4]),
      );

      await fs.copy(context, sourcePath, destPath);
      final destData = await fs.readAsBytes(context, destPath);
      expect(destData, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('throws when copying non-existent source', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/nonexistent.txt');
      final destPath = Path.fromString('/dest.txt');

      expect(
        () => fs.copy(context, sourcePath, destPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('throws when copying to existing file without overwrite', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/source.txt');
      final destPath = Path.fromString('/dest.txt');
      await fs.writeBytes(
        context,
        sourcePath,
        Uint8List.fromList([1, 2, 3, 4]),
      );
      await fs.writeBytes(context, destPath, Uint8List.fromList([5, 6, 7, 8]));

      expect(
        () async => await fs.copy(context, sourcePath, destPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.alreadyExists,
          ),
        ),
      );
    });

    test('copies directory recursively', () async {
      final context = Context();
      final fs = fsGetter();
      final sourceDir = Path.fromString('/source_dir');
      final destDir = Path.fromString('/dest_dir');
      await fs.createDirectory(context, sourceDir);
      await fs.createDirectory(context, destDir);
      final file1 = Path.fromString('/source_dir/file1.txt');
      final file2 = Path.fromString('/source_dir/file2.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));
      await fs.writeBytes(context, file2, Uint8List.fromList([4, 5, 6]));

      await fs.copy(
        context,
        sourceDir,
        destDir,
        options: const CopyOptions(recursive: true),
      );
      final copiedFile1 = Path.fromString('/dest_dir/file1.txt');
      final copiedFile2 = Path.fromString('/dest_dir/file2.txt');

      // 递归列举所有
      expect(await fs.exists(context, copiedFile1), isTrue);
      expect(await fs.exists(context, copiedFile2), isTrue);
      expect(
        await fs.readAsBytes(context, copiedFile1),
        equals(Uint8List.fromList([1, 2, 3])),
      );
      expect(
        await fs.readAsBytes(context, copiedFile2),
        equals(Uint8List.fromList([4, 5, 6])),
      );
    });

    test('throws when copying directory without recursive', () async {
      final context = Context();
      final fs = fsGetter();
      final sourceDir = Path.fromString('/source_dir');
      final destDir = Path.fromString('/dest_dir');
      await fs.createDirectory(context, sourceDir);
      await fs.createDirectory(context, destDir);
      final file1 = Path.fromString('/source_dir/file1.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));

      expect(
        () => fs.copy(context, sourceDir, destDir),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.recursiveNotSpecified,
          ),
        ),
      );
    });
  });

  group('openRead', () {
    test('reads file content', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      await fs.writeBytes(context, path, data);

      final chunks = <List<int>>[];
      await for (final chunk in fs.openRead(context, path)) {
        chunks.add(chunk);
      }

      final result = Uint8List.fromList(chunks.expand((x) => x).toList());
      expect(result, equals(data));
    });

    test('throws when reading non-existent file', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non_existent.txt');

      expect(
        () => fs.openRead(context, path).toList(),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('throws when reading a directory', () async {
      final context = Context();
      final fs = fsGetter();
      final dirPath = Path.fromString('/test_dir');
      await fs.createDirectory(context, dirPath);

      expect(
        () => fs.openRead(context, dirPath).toList(),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notAFile,
          ),
        ),
      );
    });

    test('reads partial file content', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final data = Uint8List.fromList('Hello, World!'.codeUnits);
      await fs.writeBytes(context, path, data);

      final chunks = <List<int>>[];
      await for (final chunk in fs.openRead(
        context,
        path,
        options: const ReadOptions(start: 0, end: 5),
      )) {
        chunks.add(chunk);
      }

      final result = Uint8List.fromList(chunks.expand((x) => x).toList());
      expect(result, equals(Uint8List.fromList('Hello'.codeUnits)));
    });
  });

  group('openWrite', () {
    test('opens write stream successfully', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final sink = await fs.openWrite(context, path);
      sink.add('Hello, '.codeUnits);
      sink.add('World!'.codeUnits);
      await sink.close();
      // 验证文件内容
      final content = await fs.readAsBytes(context, path);
      expect(content, equals(Uint8List.fromList('Hello, World!'.codeUnits)));
    });

    test('throws when writing to a directory', () async {
      final context = Context();
      final fs = fsGetter();
      final dirPath = Path.fromString('/test_dir');
      await fs.createDirectory(context, dirPath);

      expect(
        () => fs.openWrite(context, dirPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notAFile,
          ),
        ),
      );
    });

    test('throws when writing to non-existent parent directory', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/non_existent_dir/test_file.txt');

      expect(
        () => fs.openWrite(context, path),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('writes with append mode', skip: skipAppendWriteTest, () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final sink = await fs.openWrite(
        context,
        path,
        options: const WriteOptions(mode: WriteMode.append),
      );
      sink.add('Hello, '.codeUnits);
      await sink.close();
      // 再次打开并追加内容
      final appendSink = await fs.openWrite(
        context,
        path,
        options: const WriteOptions(mode: WriteMode.append),
      );
      appendSink.add('World!'.codeUnits);
      await appendSink.close();
      // 验证文件内容
      final content = await fs.readAsBytes(context, path);
      expect(content, equals(Uint8List.fromList('Hello, World!'.codeUnits)));
    });

    test('writes with overwrite mode', () async {
      final context = Context();
      final fs = fsGetter();
      final path = Path.fromString('/test_file.txt');
      final sink = await fs.openWrite(
        context,
        path,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );
      sink.add('Hello, '.codeUnits);
      await sink.close();
      // 再次打开并覆盖内容
      final overwriteSink = await fs.openWrite(
        context,
        path,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );
      overwriteSink.add('World!'.codeUnits);
      await overwriteSink.close();
      // 验证文件内容
      final content = await fs.readAsBytes(context, path);
      expect(content, equals(Uint8List.fromList('World!'.codeUnits)));
    });
  });

  group('move', () {
    test('moves file successfully', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/source.txt');
      final destPath = Path.fromString('/dest.txt');
      await fs.writeBytes(
        context,
        sourcePath,
        Uint8List.fromList([1, 2, 3, 4]),
      );

      await fs.move(context, sourcePath, destPath);
      expect(await fs.exists(context, sourcePath), isFalse);
      expect(await fs.exists(context, destPath), isTrue);
      final destData = await fs.readAsBytes(context, destPath);
      expect(destData, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('throws when moving non-existent source', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/non_existent.txt');
      final destPath = Path.fromString('/dest.txt');

      expect(
        () => fs.move(context, sourcePath, destPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.notFound,
          ),
        ),
      );
    });

    test('throws when moving to existing file without overwrite', () async {
      final context = Context();
      final fs = fsGetter();
      final sourcePath = Path.fromString('/source.txt');
      final destPath = Path.fromString('/dest.txt');
      await fs.writeBytes(
        context,
        sourcePath,
        Uint8List.fromList([1, 2, 3, 4]),
      );
      await fs.writeBytes(context, destPath, Uint8List.fromList([5, 6, 7, 8]));

      expect(
        () => fs.move(context, sourcePath, destPath),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.alreadyExists,
          ),
        ),
      );
    });

    test('moves directory recursively', () async {
      final context = Context();
      final fs = fsGetter();
      final sourceDir = Path.fromString('/source_dir');
      final destDir = Path.fromString('/dest_dir');
      await fs.createDirectory(context, sourceDir);
      await fs.createDirectory(context, destDir);
      final file1 = Path.fromString('/source_dir/file1.txt');
      final file2 = Path.fromString('/source_dir/file2.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));
      await fs.writeBytes(context, file2, Uint8List.fromList([4, 5, 6]));
      await fs.move(
        context,
        sourceDir,
        destDir,
        options: const MoveOptions(recursive: true),
      );
      final movedFile1 = Path.fromString('/dest_dir/file1.txt');
      final movedFile2 = Path.fromString('/dest_dir/file2.txt');
      expect(await fs.exists(context, movedFile1), isTrue);
      expect(await fs.exists(context, movedFile2), isTrue);
      expect(
        await fs.readAsBytes(context, movedFile1),
        equals(Uint8List.fromList([1, 2, 3])),
      );
      expect(
        await fs.readAsBytes(context, movedFile2),
        equals(Uint8List.fromList([4, 5, 6])),
      );
      expect(await fs.exists(context, sourceDir), isFalse);
    });
    test('throws when moving non-empty directory without recursive', () async {
      final context = Context();
      final fs = fsGetter();
      final sourceDir = Path.fromString('/source_dir');
      final destDir = Path.fromString('/dest_dir');
      await fs.createDirectory(context, sourceDir);
      final file1 = Path.fromString('/source_dir/file1.txt');
      await fs.writeBytes(context, file1, Uint8List.fromList([1, 2, 3]));

      expect(
        () => fs.move(context, sourceDir, destDir),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.code,
            'code',
            FileSystemErrorCode.recursiveNotSpecified,
          ),
        ),
      );
    });
  });
}
