import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

// 用于测试的辅助函数 - 适配 Windows
String toLocalPath(Path path, String baseDir) {
  if (path.segments.isEmpty) {
    return baseDir;
  }
  return p.join(baseDir, p.joinAll(path.segments));
}

// 创建相对于临时目录的路径
Path createTestPath(String tempDirPath, String relativePath) {
  final segments = p.split(p.normalize(relativePath));
  return Path(segments.where((s) => s.isNotEmpty && s != '.').toList());
}

void main() {
  group('LocalFileSystem', () {
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

    group('readRange', () {
      test('reads partial file content', () async {
        final path = createTestPath(tempDir.path, 'test.txt');
        final content = Uint8List.fromList('Hello, World!'.codeUnits);

        await fileSystem.writeBytes(path, content);

        final chunks = <List<int>>[];
        await for (final chunk in fileSystem.openRead(
          path,
          options: ReadOptions(start: 0, end: 5),
        )) {
          chunks.add(chunk);
        }

        final result = Uint8List.fromList(chunks.expand((x) => x).toList());
        expect(result, equals(Uint8List.fromList('Hello'.codeUnits)));
      });

      test('throws FileSystemException for non-existent file', () async {
        final path = createTestPath(tempDir.path, 'nonexistent.txt');

        expect(
          () => fileSystem.openRead(path).toList(),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.code,
              'code',
              FileSystemErrorCode.notFound,
            ),
          ),
        );
      });

      test('throws FileSystemException for directory', () async {
        final path = createTestPath(tempDir.path, 'testdir');
        final dir = Directory(p.join(tempDir.path, 'testdir'));
        await dir.create();

        expect(
          () => fileSystem.openRead(path).toList(),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.code,
              'code',
              FileSystemErrorCode.notAFile,
            ),
          ),
        );
      });
    });

    group('copy', () {
      test('throws UnimplementedError for directory copy', () async {
        final sourcePath = createTestPath(tempDir.path, 'sourcedir');
        final destPath = createTestPath(tempDir.path, 'destdir');

        final sourceDir = Directory(p.join(tempDir.path, 'sourcedir'));
        await sourceDir.create();

        expect(
          () => fileSystem.copy(sourcePath, destPath),
          throwsA(isA<UnimplementedError>()),
        );
      });
    });

    group('move', () {
      test('moves file successfully', () async {
        final sourcePath = createTestPath(tempDir.path, 'source.txt');
        final destPath = createTestPath(tempDir.path, 'dest.txt');

        final sourceFile = File(p.join(tempDir.path, 'source.txt'));
        await sourceFile.writeAsString('test content');

        await fileSystem.move(sourcePath, destPath);

        expect(await sourceFile.exists(), false);

        final destFile = File(p.join(tempDir.path, 'dest.txt'));
        expect(await destFile.exists(), true);
        expect(await destFile.readAsString(), 'test content');
      });
    });

    group('openWrite', () {
      test('opens write stream successfully', () async {
        final path = createTestPath(tempDir.path, 'test.txt');
        final sink = await fileSystem.openWrite(path);

        sink.add('Hello, '.codeUnits);
        sink.add('World!'.codeUnits);
        await sink.close();

        final file = File(p.join(tempDir.path, 'test.txt'));
        expect(await file.readAsString(), 'Hello, World!');
      });

      test('creates parent directories when needed', () async {
        final path = createTestPath(tempDir.path, 'deep/nested/test.txt');
        final sink = await fileSystem.openWrite(path);

        sink.add('test'.codeUnits);
        await sink.close();

        final file = File(p.join(tempDir.path, 'deep', 'nested', 'test.txt'));
        expect(await file.exists(), true);
        expect(await file.readAsString(), 'test');
      });
    });
  });
}
