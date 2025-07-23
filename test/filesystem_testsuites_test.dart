import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vfs_framework/core/index.dart';
import 'package:vfs_framework/filesystem/local.dart';

void testFilesystem(IFileSystem Function() fsGetter) {
  group("stat", () {
    test("return null for non-existen path", () async {
      final fs = fsGetter();
      final path = Path.fromString("/non/existent/path");
      final status = await fs.stat(path);
      expect(status, isNull);
    });
    test('returns file status for existing file', () async {
      final fs = fsGetter();

      final path = Path.fromString("/test/file.txt");
      await fs.writeBytes(path, Uint8List.fromList([1, 2, 3, 4]));
      final result = await fs.stat(path);

      expect(result, isNotNull);
      expect(result!.isDirectory, false);
      expect(result.size, equals(4));
    });
    test('returns directory status for existing directory', () async {
      final fs = fsGetter();

      final path = Path.fromString("/test");
      await fs.createDirectory(path);
      final result = await fs.stat(path);

      expect(result, isNotNull);
      expect(result!.isDirectory, true);
      expect(result.size, isNull);
    });
  });

  group("exists", () {
    test("returns false for non-existent path", () async {
      final fs = fsGetter();
      final path = Path.fromString("/non/existent/path");
      final exists = await fs.exists(path);
      expect(exists, isFalse);
    });

    test('returns true for existing file', () async {
      final fs = fsGetter();

      final path = Path.fromString("/test/file.txt");
      await fs.writeBytes(path, Uint8List.fromList([1, 2, 3, 4]));
      final exists = await fs.exists(path);

      expect(exists, isTrue);
    });

    test('returns true for existing directory', () async {
      final fs = fsGetter();

      final path = Path.fromString("/test");
      await fs.createDirectory(path);
      final exists = await fs.exists(path);

      expect(exists, isTrue);
    });

    group("createDirectory", () {
      test("create directory successfully", () async {
        final fs = fsGetter();
        final path = Path.fromString("/test");
        await fs.createDirectory(path);
        final exists = await fs.exists(path);
        expect(exists, isTrue);
      });

      test("create nested directories", () async {
        final fs = fsGetter();
        final path = Path.fromString("/test/nested/dir");
        await fs.createDirectory(
          path,
          options: CreateDirectoryOptions(recursive: true),
        );
        final exists = await fs.exists(path);
        expect(exists, isTrue);
      });

      test(
        "throws when parent does not exist and recursive is false",
        () async {
          final fs = fsGetter();
          final path = Path.fromString("/non/existent/dir");

          // 期望异常为FileSystemException并且包含notFound错误码
          expect(
            () async => fs.createDirectory(path),
            throwsA(
              isA<FileSystemException>().having(
                (e) => e.code,
                'code',
                FileSystemErrorCode.notFound,
              ),
            ),
          );
        },
      );
      test("throws when trying to create a file as a directory", () async {
        final fs = fsGetter();
        final path = Path.fromString("/test/file.txt");
        await fs.writeBytes(path, Uint8List.fromList([1, 2, 3, 4]));

        // 期望异常为FileSystemException并且包含notADirectory错误码
        expect(
          () async => fs.createDirectory(path),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.code,
              'code',
              FileSystemErrorCode.alreadyExists,
            ),
          ),
        );
      });

      test("throws when trying to create an existing directory", () async {
        final fs = fsGetter();
        final path = Path.fromString("/test");
        await fs.createDirectory(path);

        // 期望异常为FileSystemException并且包含alreadyExists错误码
        expect(
          () async => fs.createDirectory(path),
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
  });

  group("delete", () {
    test("deletes file successfully", () async {
      final fs = fsGetter();
      final path = Path.fromString("/test/file.txt");
      await fs.writeBytes(path, Uint8List.fromList([1, 2, 3, 4]));
      expect(await fs.exists(path), isTrue);

      await fs.delete(path);
      expect(await fs.exists(path), isFalse);
    });

    test("deletes empty directory successfully", () async {
      final fs = fsGetter();

      // 创建一个空目录
      final path = Path.fromString("/dir");
      await fs.createDirectory(path);

      // 确认是个空目录
      expect(await fs.stat(path), isNotNull);
      expect((await fs.stat(path))!.isDirectory, isTrue);
      expect((await fs.stat(path))!.size, isNull);
      expect(await fs.exists(path), isTrue);
      expect(await fs.list(path).isEmpty, isTrue);

      await fs.delete(path);
      expect(await fs.exists(path), isFalse);
    });

    test("deletes non-empty directory with recursive option", () async {
      final fs = fsGetter();

      // 创建一个非空目录
      final dirPath = Path.fromString("/test/dir");
      await fs.createDirectory(
        dirPath,
        options: CreateDirectoryOptions(recursive: true),
      );
      final filePath = Path.fromString("/test/dir/file.txt");
      await fs.writeBytes(filePath, Uint8List.fromList([1, 2, 3, 4]));

      // 确认目录和文件存在
      expect(await fs.exists(dirPath), isTrue);
      expect(await fs.exists(filePath), isTrue);

      // 删除目录
      await fs.delete(dirPath, options: DeleteOptions(recursive: true));
      expect(await fs.exists(dirPath), isFalse);
      expect(await fs.exists(filePath), isFalse);
    });

    test("throws when deleting non-existent path", () async {
      final fs = fsGetter();
      final path = Path.fromString("/non/existent/path");

      expect(
        () => fs.delete(path),
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
      "throws when deleting non-empty directory without recursive",
      () async {
        final fs = fsGetter();
        final dirPath = Path.fromString("/test/dir");
        final filePath = Path.fromString("/test/dir/file.txt");

        await fs.createDirectory(
          dirPath,
          options: CreateDirectoryOptions(recursive: true),
        );
        await fs.writeBytes(filePath, Uint8List.fromList([1, 2, 3, 4]));

        expect(
          () => fs.delete(dirPath),
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
}

void main() {
  group("test LocalFileSystem", () {
    late LocalFileSystem fileSystem;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('filesystem_test_');
      // 使用临时目录作为基础目录创建文件系统
      fileSystem = LocalFileSystem(baseDir: tempDir.path);
    });
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testFilesystem(() => fileSystem);
  });
}
