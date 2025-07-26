import 'dart:async';
import 'dart:typed_data';

import 'package:vfs_framework/src/helper/filesystem_helper.dart';
import 'package:vfs_framework/src/helper/mime_type_helper.dart';

import '../abstract/index.dart';

class _MemoryFileEntity {
  String get name => status.path.segments.last;
  FileStatus status;
  // 如果是文件则有内容
  Uint8List? content;
  // 如果是目录则有子项
  Set<_MemoryFileEntity>? children;
  _MemoryFileEntity(this.status, {this.children});
}

class MemoryFileSystem extends IFileSystem with FileSystemHelper {
  final _rootDir = _MemoryFileEntity(
    FileStatus(path: Path([]), isDirectory: true),
    children: {},
  );

  _MemoryFileEntity? _getEntity(Path path) {
    if (path.segments.isEmpty) return _rootDir;

    var current = _rootDir;
    for (final segment in path.segments) {
      final child = current.children
          ?.where((e) => e.name == segment)
          .firstOrNull;
      if (child == null) return null;
      current = child;
    }
    return current;
  }

  Stream<FileStatus> nonRecursiveList(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final entity = _getEntity(path);
    if (entity == null || !entity.status.isDirectory) {
      throw FileSystemException.notFound(path);
    }

    for (final child in entity.children!) {
      yield child.status;
    }
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    // 遍历目录
    return listImplByNonRecursive(
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  Future<void> nonRecursiveCopyFile(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    return copyFileByReadAndWrite(
      source,
      destination,
      openWrite: openWrite,
      openRead: openRead,
    );
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    return copyImplByNonRecursive(
      source: source,
      destination: destination,
      options: options,
      nonRecursiveCopyFile: nonRecursiveCopyFile,
      nonRecursiveList: nonRecursiveList,
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
    );
  }

  Future<void> nonRecursiveCreateDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    // 先寻找到path的父目录
    final parentDir = path.parent;
    if (parentDir == null) {
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentDir);
    // 如果父目录不存在，报错
    if (parentEntity == null) {
      throw FileSystemException.notFound(parentDir);
    }
    // 如果父目录不是目录，报错
    if (!parentEntity.status.isDirectory) {
      throw FileSystemException.notADirectory(parentDir);
    }
    // 直接创建
    parentEntity.children!.add(
      _MemoryFileEntity(
        FileStatus(path: path, isDirectory: true),
        children: {},
      ),
    );
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    return createDirectoryImplByNonRecursive(
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
      path: path,
      options: options,
    );
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    // 寻找文件或目录
    final entity = _getEntity(path);
    if (entity == null) {
      throw FileSystemException.notFound(path);
    }
    // 如果是目录，检查是否为空
    if (entity.status.isDirectory &&
        entity.children!.isNotEmpty &&
        !options.recursive) {
      throw FileSystemException.notEmptyDirectory(path);
    }
    // 从父目录中删除
    final parentPath = path.parent;
    if (parentPath == null) {
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      throw FileSystemException.notADirectory(parentPath);
    }
    parentEntity.children!.remove(entity);
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    await preOpenReadCheck(path, options: options);
    final entity = _getEntity(path);
    assert(entity != null, 'File not found: $path');
    assert(!entity!.status.isDirectory, 'Cannot read a directory: $path');
    final content = entity!.content!;

    final start = options.start ?? 0;
    final end = options.end ?? content.length;
    yield content.sublist(start, end);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    // 预检查所有
    await preOpenWriteCheck(path, options: options);
    final parentPath = path.parent;
    if (parentPath == null) {
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      throw FileSystemException.notADirectory(parentPath);
    }

    // 查找是否已存在这个文件
    final existingEntity = parentEntity.children
        ?.where((e) => e.name == path.filename)
        .firstOrNull;
    parentEntity.children?.remove(existingEntity);

    // 创建或覆盖文件
    final newEntity = _MemoryFileEntity(
      FileStatus(
        path: path, 
        isDirectory: false,
        mimeType: MimeTypeHelper.getMimeType(path.filename ?? ''),
      ),
    );
    parentEntity.children!.add(newEntity); // 添加新文件

    // 如果是覆盖或追加模式，处理内容
    if (options.mode == WriteMode.append) {
      if (existingEntity != null) {
        newEntity.content = existingEntity.content; // 继承旧内容
      }
    }
    // 返回一个Sink来写入数据
    final controller = StreamController<List<int>>();
    controller.stream.listen(
      (data) {
        newEntity.content ??= Uint8List(0);
        newEntity.content = Uint8List.fromList(newEntity.content! + data);
        newEntity.status = FileStatus(
          path: path,
          isDirectory: false,
          size: newEntity.content!.length,
          mimeType: MimeTypeHelper.getMimeType(path.filename ?? ''),
        );
      },
      onDone: () {
        controller.close();
      },
      onError: (error) {
        controller.addError(error);
      },
    );
    return controller.sink;
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) => Future.value(_getEntity(path)?.status);
}
