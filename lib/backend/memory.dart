import 'dart:async';
import 'dart:typed_data';

import 'package:vfs_framework/helper/filesystem_helper.dart';

import '../abstract/index.dart';

class MemoryFileSystem extends IFileSystem with FileSystemHelper {
  final _files = <String, Uint8List>{};
  final _directories = <String, bool>{};
  final _fileMetadata = <String, DateTime>{};
  final _dirMetadata = <String, DateTime>{};

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final key = path.toString();

    if (_files.containsKey(key)) {
      return FileStatus(
        path: path,
        size: _files[key]!.length,
        isDirectory: false,
      );
    }

    if (_directories.containsKey(key)) {
      return FileStatus(path: path, size: null, isDirectory: true);
    }

    return null;
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final prefix = '${_normalizePath(path.toString())}/';
    final seen = <String>{};

    // 列出文件
    for (final filePath in _files.keys) {
      if (filePath.startsWith(prefix)) {
        final relativePath = filePath.substring(prefix.length);
        final segments = relativePath.split('/');

        if (segments.length == 1) {
          yield FileStatus(
            path: Path.fromString(filePath),
            size: _files[filePath]!.length,
            isDirectory: false,
          );
        } else if (segments.length > 1) {
          final dirPath = '$prefix${segments[0]}';
          if (!seen.contains(dirPath)) {
            seen.add(dirPath);
            yield FileStatus(
              path: Path.fromString(dirPath),
              size: null,
              isDirectory: true,
            );
          }
        }
      }
    }

    // 列出目录
    for (final dir in _directories.keys) {
      if (dir.startsWith(prefix) && dir != prefix) {
        final relativePath = dir.substring(prefix.length);
        final segments = relativePath.split('/');

        if (segments.isNotEmpty) {
          final currentPath = '$prefix${segments[0]}';
          if (!seen.contains(currentPath)) {
            seen.add(currentPath);
            yield FileStatus(
              path: Path.fromString(currentPath),
              size: null,
              isDirectory: true,
            );
          }
        }
      }
    }
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    final srcKey = source.toString();
    final destKey = destination.toString();

    if (_files.containsKey(srcKey)) {
      _files[destKey] = Uint8List.fromList(_files[srcKey]!);
      _fileMetadata[destKey] = DateTime.now();
    } else if (_directories.containsKey(srcKey)) {
      // 递归复制目录
      await _copyDirectory(source, destination);
    } else {
      throw FileSystemException.notFound(source);
    }
  }

  Future<void> _copyDirectory(Path source, Path destination) async {
    final srcPrefix = _normalizePath(source.toString());
    final destPrefix = _normalizePath(destination.toString());

    // 创建目标目录
    await createDirectory(destination);

    // 复制子文件
    for (final filePath in _files.keys) {
      if (filePath.startsWith('$srcPrefix/')) {
        final relativePath = filePath.substring(srcPrefix.length + 1);
        final destPath = '$destPrefix/$relativePath';
        _files[destPath] = Uint8List.fromList(_files[filePath]!);
        _fileMetadata[destPath] = DateTime.now();
      }
    }

    // 复制子目录
    for (final dirPath in _directories.keys) {
      if (dirPath.startsWith('$srcPrefix/') && dirPath != srcPrefix) {
        final relativePath = dirPath.substring(srcPrefix.length + 1);
        final destPath = '$destPrefix/$relativePath';
        _directories[destPath] = true;
        _dirMetadata[destPath] = DateTime.now();
      }
    }
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    final key = _normalizePath(path.toString());

    if (_files.containsKey(key)) {
      throw FileSystemException.notADirectory(path);
    }

    if (_directories.containsKey(key)) {
      return;
    }

    // 递归创建父目录
    if (options.createParents) {
      Path? current = path;
      while (current != null) {
        final currentKey = current.toString();
        if (!_directories.containsKey(currentKey)) {
          _directories[currentKey] = true;
          _dirMetadata[currentKey] = DateTime.now();
        }
        current = current.parent;
      }
    } else {
      // 检查父目录是否存在
      final parent = path.parent;
      if (parent != null && !_directories.containsKey(parent.toString())) {
        throw FileSystemException.notFound(parent);
      }
      _directories[key] = true;
      _dirMetadata[key] = DateTime.now();
    }
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final key = _normalizePath(path.toString());

    if (_files.containsKey(key)) {
      _files.remove(key);
      _fileMetadata.remove(key);
    } else if (_directories.containsKey(key)) {
      // 检查目录是否为空
      final hasChildren =
          _files.keys.any((k) => k.startsWith('$key/')) ||
          _directories.keys.any((d) => d.startsWith('$key/') && d != key);

      if (hasChildren && !options.recursive) {
        throw FileSystemException(
          code: FileSystemErrorCode.ioError,
          message: 'Directory not empty',
          path: path,
        );
      }

      // 删除目录内容
      _files.removeWhere((k, _) => k.startsWith('$key/'));
      _fileMetadata.removeWhere((k, _) => k.startsWith('$key/'));

      _directories.removeWhere((d, _) => d.startsWith('$key/') || d == key);
      _dirMetadata.removeWhere((d, _) => d.startsWith('$key/') || d == key);
    } else {
      throw FileSystemException.notFound(path);
    }
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final controller = StreamController<List<int>>();
    var buffer = Uint8List(0);

    controller.stream.listen(
      (chunk) {
        buffer = Uint8List.fromList([...buffer, ...chunk]);
      },
      onDone: () async {
        final key = path.toString();

        // 检查是否允许覆盖
        if (_files.containsKey(key) && !options.overwrite && !options.append) {
          controller.addError(FileSystemException.alreadyExists(path));
          return;
        }

        // 确保父目录存在
        final parent = path.parent;
        if (parent != null) {
          await createDirectory(
            parent,
            options: CreateDirectoryOptions(createParents: true),
          );
        }

        // 追加或覆盖内容
        if (options.append && _files.containsKey(key)) {
          final existing = _files[key]!;
          _files[key] = Uint8List.fromList([...existing, ...buffer]);
        } else {
          _files[key] = buffer;
        }

        _fileMetadata[key] = DateTime.now();
        controller.close();
      },
      onError: controller.addError,
    );

    return controller.sink;
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    final key = path.toString();

    if (!_files.containsKey(key)) {
      throw FileSystemException.notFound(path);
    }

    final data = _files[key]!;
    final start = options.start ?? 0;
    final end = options.end ?? data.length;

    if (start < 0 || end > data.length || start > end) {
      throw RangeError(
        'Invalid read range: $start-$end (length: ${data.length})',
      );
    }

    yield data.sublist(start, end);
  }

  // 辅助方法：标准化路径
  String _normalizePath(String path) {
    return path.replaceAll(RegExp(r'/{2,}'), '/').replaceAll(RegExp(r'/$'), '');
  }
}
