import 'dart:convert';
import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:vfs_framework/vfs_framework.dart';

Future<void> clearFileSystem(IFileSystem fs) async {
  final context = Context();
  for (final entry in await fs.list(context, Path.rootPath).toList()) {
    try {
      if (entry.isDirectory) {
        await fs.delete(
          context,
          entry.path,
          options: const DeleteOptions(recursive: true),
        );
      } else {
        await fs.delete(context, entry.path);
      }
    } on FileSystemException catch (e) {
      if (e.code == FileSystemErrorCode.notFound) {
        // 如果文件已被删除，忽略错误
        continue;
      }
      // 其他错误抛出
      rethrow;
    }
  }
}

class Emitter implements ScoreEmitter {
  const Emitter();

  @override
  void emit(String testName, double value) {
    // 计算1s可以执行多少次
    final timesPerSecond = (1e6 / value).round();
    print(
      '$testName: '
      '${value.toStringAsFixed(2)} us. '
      'Approximately $timesPerSecond ops.',
    );
  }
}

class BenchmarkFileSystemStat extends AsyncBenchmarkBase {
  BenchmarkFileSystemStat({
    required this.fileSystem,
    required this.exists,
    required this.isDirectory,
  }) : super(
         '[${fileSystem.runtimeType}.stat '
         '${{'exists': exists, 'isDirectory': isDirectory}}]',
         emitter: const Emitter(),
       );
  final IFileSystem fileSystem;
  final bool exists;
  final bool isDirectory;

  @override
  Future<void> run() async {
    final context = Context();
    final ret = await fileSystem.stat(context, Path.fromString('/stat'));
    if (exists) {
      if (isDirectory) {
        assert(ret!.isDirectory == true);
        assert(ret!.size == null);
      } else {
        assert(ret?.isDirectory == false);
        assert(ret!.size! > 0);
      }
    } else {
      assert(ret == null);
    }
  }

  @override
  Future<void> setup() async {
    final context = Context();
    if (exists) {
      if (isDirectory) {
        await fileSystem.createDirectory(
          context,
          Path.fromString('/stat'),
          options: const CreateDirectoryOptions(),
        );
      } else {
        final s = await fileSystem.openWrite(
          context,
          Path.fromString('/stat'),
          options: const WriteOptions(),
        );
        s.add(utf8.encode('This is a test file for benchmarking.'));
        await s.close();
      }
    } else {
      if (await fileSystem.exists(context, Path.fromString('/stat'))) {
        throw StateError('File or directory should not exist, but it does.');
      }
    }
  }

  @override
  Future<void> teardown() {
    return clearFileSystem(fileSystem);
  }
}

void testFileSystemStat(IFileSystem fileSystem) {
  group('${fileSystem.runtimeType}.stat benchmark test', () {
    for (final exists in [true, false]) {
      for (final isDirectory in [true, false]) {
        test('[${fileSystem.runtimeType}.stat '
            '${{'exists': exists, 'isDirectory': isDirectory}}]', () async {
          await BenchmarkFileSystemStat(
            fileSystem: fileSystem,
            exists: exists,
            isDirectory: isDirectory,
          ).report();
        });
      }
    }
  });
}

void main() async {
  group('test stat', () {
    group('MemoryFileSystem', skip: true, () {
      testFileSystemStat(MemoryFileSystem());
    });
    group('WebDAVFileSystem', skip: true, () {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8091'));
      dio.interceptors.add(
        const WebDAVBasicAuthInterceptor(username: 'admin', password: 'test'),
      );
      final fs = WebDAVFileSystem(dio);
      testFileSystemStat(fs);
    });
    group('AliasFileSystem', skip: true, () {
      IFileSystem fs;
      fs = MemoryFileSystem();
      fs = AliasFileSystem(fileSystem: fs);
      testFileSystemStat(fs);
    });
    group('LocalFileSystem', () {
      testFileSystemStat(LocalFileSystem(baseDir: Directory('./tmp')));
    });
  });
}
