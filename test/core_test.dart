import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

void main() {
  group('Path', () {
    test('fromString handles basic paths', () {
      expect(
        Path.fromString('/home/user/file.txt').segments,
        equals(['home', 'user', 'file.txt']),
      );
      expect(
        Path.fromString('relative/path').segments,
        equals(['relative', 'path']),
      );
      expect(Path.fromString('/').segments, isEmpty);
    });

    test('fromString handles path normalization', () {
      expect(
        Path.fromString('/home/../user/./file.txt').segments,
        equals(['user', 'file.txt']),
      );
      expect(
        Path.fromString('//double//slash//').segments,
        equals(['double', 'slash']),
      );
      expect(Path.fromString('../../up/down').segments, equals(['up', 'down']));
    });

    test('filename property', () {
      expect(
        Path.fromString('/home/user/file.txt').filename,
        equals('file.txt'),
      );
      expect(Path.fromString('/home/user').filename, equals('user'));
      expect(Path.rootPath.filename, isNull);
    });

    test('parent property', () {
      final path = Path.fromString('/home/user/file.txt');
      expect(path.parent?.segments, equals(['home', 'user']));
      expect(Path.rootPath.parent, isNull);
    });

    test('toString', () {
      expect(
        Path.fromString('/home/user/file.txt').toString(),
        equals('/home/user/file.txt'),
      );
      expect(Path.rootPath.toString(), equals('/'));
    });

    test('equality', () {
      final path1 = Path.fromString('/home/user');
      final path2 = Path.fromString('/home/user');
      final path3 = Path.fromString('/home/other');

      expect(path1, equals(path2));
      expect(path1, isNot(equals(path3)));
    });
  });

  group('FileStatus', () {
    test('equality and props', () {
      final status1 = FileStatus(
        isDirectory: true,
        path: Path.fromString('/test'),
        size: 100,
      );
      final status2 = FileStatus(
        isDirectory: true,
        path: Path.fromString('/test'),
        size: 100,
      );
      final status3 = FileStatus(
        isDirectory: false,
        path: Path.fromString('/test'),
        size: 100,
      );

      expect(status1, equals(status2));
      expect(status1, isNot(equals(status3)));
    });
  });

  group('FileSystemException', () {
    test('factory constructors', () {
      final path = Path.fromString('/test');

      final notFound = FileSystemException.notFound(path);
      expect(notFound.code, FileSystemErrorCode.notFound);
      expect(notFound.path, path);

      final notAFile = FileSystemException.notAFile(path);
      expect(notAFile.code, FileSystemErrorCode.notAFile);

      final notADirectory = FileSystemException.notADirectory(path);
      expect(notADirectory.code, FileSystemErrorCode.notADirectory);

      final permissionDenied = FileSystemException.permissionDenied(path);
      expect(permissionDenied.code, FileSystemErrorCode.permissionDenied);

      final unsupported = FileSystemException.unsupportedEntity(path);
      expect(unsupported.code, FileSystemErrorCode.unsupportedEntity);
    });

    test('toString', () {
      final exception = FileSystemException.notFound(Path.fromString('/test'));
      expect(
        exception.toString(),
        contains('FileSystemException(FileSystemErrorCode.notFound, /test)'),
      );
    });
  });
}
