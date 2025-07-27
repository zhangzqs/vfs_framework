import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import '../helper/mime_type_helper.dart';

class _MemoryFileEntity {
  _MemoryFileEntity(this.status, {Map<String, _MemoryFileEntity>? children})
    : children = children;

  String get name => status.path.segments.last;
  FileStatus status;
  // 如果是文件则有内容
  Uint8List? content;
  // 如果是目录则有子项 - 使用Map优化查找性能
  Map<String, _MemoryFileEntity>? children;

  // 使用BytesBuilder优化写入性能
  BytesBuilder? _writeBuffer;

  /// 添加写入数据到缓冲区
  void addWriteData(List<int> data) {
    _writeBuffer ??= BytesBuilder();
    _writeBuffer!.add(data);
  }

  /// 刷新写入缓冲区到内容
  void flushWriteBuffer() {
    if (_writeBuffer == null || _writeBuffer!.isEmpty) return;

    // BytesBuilder.toBytes() 已经是高度优化的
    content = _writeBuffer!.toBytes();
    final totalSize = content!.length;

    // 清理缓冲区
    _writeBuffer = null;

    // 更新文件状态
    status = FileStatus(
      path: status.path,
      isDirectory: false,
      size: totalSize,
      mimeType: status.mimeType,
    );
  }

  /// 获取当前缓冲区大小（用于性能监控）
  int get bufferSize => _writeBuffer?.length ?? 0;
}

class MemoryFileSystem extends IFileSystem with FileSystemHelper {
  MemoryFileSystem() : logger = Logger('MemoryFileSystem');

  @override
  final Logger logger;
  final _rootDir = _MemoryFileEntity(
    FileStatus(path: Path([]), isDirectory: true),
    children: <String, _MemoryFileEntity>{},
  );

  // 性能统计
  int _readOperations = 0;
  int _writeOperations = 0;
  int _listOperations = 0;
  int _totalBytesRead = 0;
  int _totalBytesWritten = 0;
  int _bufferFlushCount = 0;
  int _maxBufferSize = 0;

  /// 获取性能统计信息
  Map<String, dynamic> getPerformanceStats() {
    return {
      'readOperations': _readOperations,
      'writeOperations': _writeOperations,
      'listOperations': _listOperations,
      'totalBytesRead': _totalBytesRead,
      'totalBytesWritten': _totalBytesWritten,
      'bufferFlushCount': _bufferFlushCount,
      'maxBufferSize': _maxBufferSize,
      'totalEntities': _countEntities(_rootDir),
      'memoryUsage': _calculateMemoryUsage(),
    };
  }

  int _countEntities(_MemoryFileEntity entity) {
    var count = 1;
    if (entity.children != null) {
      for (final child in entity.children!.values) {
        count += _countEntities(child);
      }
    }
    return count;
  }

  /// 计算内存使用量（字节）
  int _calculateMemoryUsage() {
    return _calculateEntityMemoryUsage(_rootDir);
  }

  int _calculateEntityMemoryUsage(_MemoryFileEntity entity) {
    var usage = 0;

    // 文件内容占用的内存
    if (entity.content != null) {
      usage += entity.content!.length;
    }

    // 写入缓冲区占用的内存
    usage += entity.bufferSize;

    // 递归计算子实体
    if (entity.children != null) {
      for (final child in entity.children!.values) {
        usage += _calculateEntityMemoryUsage(child);
      }
    }

    return usage;
  }

  /// 清空性能统计
  void resetPerformanceStats() {
    _readOperations = 0;
    _writeOperations = 0;
    _listOperations = 0;
    _totalBytesRead = 0;
    _totalBytesWritten = 0;
    _bufferFlushCount = 0;
    _maxBufferSize = 0;
  }

  _MemoryFileEntity? _getEntity(Path path) {
    logger.finest('Getting entity for path: $path');
    if (path.segments.isEmpty) return _rootDir;

    var current = _rootDir;
    for (final segment in path.segments) {
      final child = current.children?[segment];
      if (child == null) {
        logger.finest('Entity not found at segment: $segment in path: $path');
        return null;
      }
      current = child;
    }
    logger.finest('Found entity for path: $path');
    return current;
  }

  Stream<FileStatus> nonRecursiveList(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    logger.fine('Listing directory: $path');
    _listOperations++;

    final entity = _getEntity(path);
    if (entity == null || !entity.status.isDirectory) {
      logger.warning('Directory not found or not a directory: $path');
      throw FileSystemException.notFound(path);
    }

    final childCount = entity.children!.length;
    logger.fine('Found $childCount children in directory: $path');

    for (final child in entity.children!.values) {
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
    logger.fine('Creating directory: $path');
    // 先寻找到path的父目录
    final parentDir = path.parent;
    if (parentDir == null) {
      logger.warning('Cannot create directory: no parent path for $path');
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentDir);
    // 如果父目录不存在，报错
    if (parentEntity == null) {
      logger.warning('Parent directory not found: $parentDir');
      throw FileSystemException.notFound(parentDir);
    }
    // 如果父目录不是目录，报错
    if (!parentEntity.status.isDirectory) {
      logger.warning('Parent is not a directory: $parentDir');
      throw FileSystemException.notADirectory(parentDir);
    }

    final dirName = path.filename!;
    // 检查是否已存在
    if (parentEntity.children!.containsKey(dirName)) {
      logger.warning('Directory already exists: $path');
      throw FileSystemException.alreadyExists(path);
    }

    // 直接创建
    final newDir = _MemoryFileEntity(
      FileStatus(path: path, isDirectory: true),
      children: <String, _MemoryFileEntity>{},
    );
    parentEntity.children![dirName] = newDir;
    logger.fine('Directory created successfully: $path');
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
    logger.fine('Deleting: $path (recursive: ${options.recursive})');
    // 寻找文件或目录
    final entity = _getEntity(path);
    if (entity == null) {
      logger.warning('Delete failed: entity not found: $path');
      throw FileSystemException.notFound(path);
    }
    // 如果是目录，检查是否为空
    if (entity.status.isDirectory &&
        entity.children!.isNotEmpty &&
        !options.recursive) {
      logger.warning('Delete failed: directory not empty: $path');
      throw FileSystemException.notEmptyDirectory(path);
    }
    // 从父目录中删除
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning('Delete failed: no parent path: $path');
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        'Delete failed: parent not found or not directory: $parentPath',
      );
      throw FileSystemException.notADirectory(parentPath);
    }

    final fileName = path.filename!;
    final removed = parentEntity.children!.remove(fileName);
    if (removed != null) {
      logger.fine('Successfully deleted: $path');
    } else {
      logger.warning(
        'Delete failed: file not found in parent directory: $path',
      );
    }
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    logger.fine(
      'Opening read stream for: $path (start: ${options.start}, '
      'end: ${options.end})',
    );
    _readOperations++;

    await preOpenReadCheck(path, options: options);
    final entity = _getEntity(path);
    assert(entity != null, 'File not found: $path');
    assert(!entity!.status.isDirectory, 'Cannot read a directory: $path');
    final content = entity!.content!;

    final start = options.start ?? 0;
    final end = options.end ?? content.length;
    final readSize = end - start;
    _totalBytesRead += readSize;

    logger.fine('Reading $readSize bytes from $path ($start-$end)');
    yield content.sublist(start, end);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    logger.fine('Opening write stream for: $path (mode: ${options.mode})');
    // 预检查所有
    await preOpenWriteCheck(path, options: options);
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning('Write failed: no parent path for $path');
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        'Write failed: parent not found or not directory: $parentPath',
      );
      throw FileSystemException.notADirectory(parentPath);
    }

    final fileName = path.filename!;
    // 查找是否已存在这个文件
    final existingEntity = parentEntity.children![fileName];

    // 创建或覆盖文件
    final newEntity = _MemoryFileEntity(
      FileStatus(
        path: path,
        isDirectory: false,
        mimeType: detectMimeType(fileName),
      ),
    );

    // 如果是追加模式，继承旧内容
    if (options.mode == WriteMode.append && existingEntity != null) {
      newEntity.addWriteData(existingEntity.content!);
      logger.fine('Appending to existing file: $path');
    } else {
      logger.fine('Creating new file or overwriting: $path');
    }

    parentEntity.children![fileName] = newEntity; // 添加新文件

    // 返回一个优化的Sink来写入数据
    final controller = StreamController<List<int>>();
    controller.stream.listen(
      (data) {
        logger.finest('Writing ${data.length} bytes to $path');
        _totalBytesWritten += data.length;
        newEntity.addWriteData(data);

        // 监控最大缓冲区大小
        final currentBufferSize = newEntity.bufferSize;
        if (currentBufferSize > _maxBufferSize) {
          _maxBufferSize = currentBufferSize;
        }
      },
      onDone: () {
        _writeOperations++;
        _bufferFlushCount++;

        final bufferSizeBeforeFlush = newEntity.bufferSize;
        newEntity.flushWriteBuffer();

        logger.fine(
          'Write completed for $path, final size: '
          '${newEntity.content?.length ?? 0} bytes, '
          'buffer size before flush: $bufferSizeBeforeFlush bytes',
        );
        controller.close();
      },
      onError: (Object error, StackTrace? stackTrace) {
        logger.warning('Write error for $path: $error');
        controller.addError(error, stackTrace);
      },
    );
    return controller.sink;
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    logger.finest('Getting status for: $path');
    final entity = _getEntity(path);
    if (entity == null) {
      logger.finest('Status not found for: $path');
      return null;
    }

    // 确保文件大小是最新的
    if (!entity.status.isDirectory && entity.content != null) {
      if (entity.status.size != entity.content!.length) {
        entity.status = FileStatus(
          path: path,
          isDirectory: false,
          size: entity.content!.length,
          mimeType: entity.status.mimeType,
        );
      }
    }

    logger.finest(
      'Status found for $path: isDirectory=${entity.status.isDirectory}, '
      'size=${entity.status.size}',
    );
    return entity.status;
  }

  /// 批量写入文件的优化方法，避免Stream的开销
  Future<void> writeBytesDirect(
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    logger.fine(
      'Direct writing ${data.length} bytes to: $path (mode: ${options.mode})',
    );

    // 预检查
    await preOpenWriteCheck(path, options: options);
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning('Write failed: no parent path for $path');
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        'Write failed: parent not found or not directory: $parentPath',
      );
      throw FileSystemException.notADirectory(parentPath);
    }

    final fileName = path.filename!;
    final existingEntity = parentEntity.children![fileName];

    // 创建或更新文件
    final newEntity = _MemoryFileEntity(
      FileStatus(
        path: path,
        isDirectory: false,
        size: data.length,
        mimeType: detectMimeType(fileName),
      ),
    );

    // 根据写入模式处理内容
    if (options.mode == WriteMode.append && existingEntity?.content != null) {
      // 追加模式：使用BytesBuilder高效合并
      final builder = BytesBuilder();
      builder.add(existingEntity!.content!);
      builder.add(data);
      newEntity.content = builder.toBytes();
      logger.fine(
        'Appended to existing file: $path, '
        'new size: ${newEntity.content!.length}',
      );
    } else {
      // 覆盖或新建模式
      newEntity.content = data;
      logger.fine('Created/overwrote file: $path, size: ${data.length}');
    }

    parentEntity.children![fileName] = newEntity;

    // 更新统计
    _writeOperations++;
    _totalBytesWritten += data.length;

    logger.fine('Direct write completed for $path');
  }

  /// 高效的文件拷贝方法，直接操作内存
  Future<void> copyDirect(
    Path source,
    Path destination, {
    bool overwrite = false,
  }) async {
    logger.fine('Direct copying from $source to $destination');

    final sourceEntity = _getEntity(source);
    if (sourceEntity == null) {
      throw FileSystemException.notFound(source);
    }

    if (sourceEntity.status.isDirectory) {
      throw FileSystemException.notAFile(source);
    }

    if (sourceEntity.content == null) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Source file has no content',
        path: source,
      );
    }

    // 直接拷贝内容，避免流式读写的开销
    await writeBytesDirect(
      destination,
      sourceEntity.content!,
      options: WriteOptions(
        mode: overwrite ? WriteMode.overwrite : WriteMode.write,
      ),
    );

    logger.fine('Direct copy completed: $source -> $destination');
  }
}
