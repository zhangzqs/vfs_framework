import 'dart:async';
import 'dart:typed_data';

import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import '../helper/mime_type_helper.dart';
import '../logger/index.dart';

class _MemoryFileEntity {
  _MemoryFileEntity(this.status, {this.children});

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
  MemoryFileSystem();

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

  _MemoryFileEntity? _getEntity(Context context, Path path) {
    final logger = context.logger;
    logger.trace(
      '获取实体',
      metadata: {'path': path.toString(), 'operation': 'get_entity'},
    );
    if (path.segments.isEmpty) return _rootDir;

    var current = _rootDir;
    for (final segment in path.segments) {
      final child = current.children?[segment];
      if (child == null) {
        logger.trace(
          '实体未找到',
          metadata: {
            'segment': segment,
            'path': path.toString(),
            'operation': 'entity_not_found_at_segment',
          },
        );
        return null;
      }
      current = child;
    }
    logger.trace(
      '找到实体',
      metadata: {'path': path.toString(), 'operation': 'entity_found'},
    );
    return current;
  }

  Stream<FileStatus> nonRecursiveList(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final logger = context.logger;
    logger.debug(
      '列举目录',
      metadata: {'path': path.toString(), 'operation': 'list_directory'},
    );
    _listOperations++;

    final entity = _getEntity(context, path);
    if (entity == null) {
      logger.warning(
        '目录未找到',
        metadata: {'path': path.toString(), 'operation': 'directory_not_found'},
      );
      throw FileSystemException.notFound(path);
    }
    if (!entity.status.isDirectory) {
      logger.warning(
        '路径不是目录',
        metadata: {'path': path.toString(), 'operation': 'path_not_directory'},
      );
      throw FileSystemException.notADirectory(path);
    }

    final childCount = entity.children!.length;
    logger.debug(
      '目录中找到子项',
      metadata: {
        'path': path.toString(),
        'child_count': childCount,
        'operation': 'found_children_in_directory',
      },
    );

    for (final child in entity.children!.values) {
      yield child.status;
    }
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    final logger = context.logger;
    logger.log(
      Level.debug,
      '列举目录',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'list_directory',
      },
    );

    if (!options.recursive) {
      return nonRecursiveList(context, path, options: options);
    }

    // For recursive listing, we need to implement it here
    return _recursiveList(context, path, options);
  }

  Stream<FileStatus> _recursiveList(
    Context context,
    Path path,
    ListOptions options,
  ) async* {
    final queue = <Path>[path];
    final seen = <Path>{};

    while (queue.isNotEmpty) {
      final currentPath = queue.removeLast();
      if (seen.contains(currentPath)) continue;
      seen.add(currentPath);

      await for (final status in nonRecursiveList(
        context,
        currentPath,
        options: options,
      )) {
        yield status;
        if (status.isDirectory) {
          queue.add(status.path);
        }
      }
    }
  }

  Future<void> nonRecursiveCopyFile(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    // 简单实现：读取源文件内容，写入目标文件
    final sourceEntity = _getEntity(context, source);
    if (sourceEntity == null) {
      throw FileSystemException.notFound(source);
    }
    if (sourceEntity.status.isDirectory) {
      throw FileSystemException.recursiveNotSpecified(source);
    }

    final content = sourceEntity.content!;
    await writeBytesDirect(
      context,
      destination,
      content,
      options: WriteOptions(
        mode: options.overwrite ? WriteMode.overwrite : WriteMode.write,
      ),
    );
  }

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    // 简化实现，直接在这里处理
    final logger = context.logger;
    logger.debug(
      '复制文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': options.overwrite,
        'recursive': options.recursive,
        'operation': 'copy_file',
      },
    );

    final sourceEntity = _getEntity(context, source);
    if (sourceEntity == null) {
      throw FileSystemException.notFound(source);
    }

    if (sourceEntity.status.isDirectory) {
      if (!options.recursive) {
        throw FileSystemException.recursiveNotSpecified(source);
      }
      // 创建目录
      await createDirectory(
        context,
        destination,
        options: const CreateDirectoryOptions(createParents: true),
      );

      if (options.recursive) {
        // 递归复制子项
        await for (final child in nonRecursiveList(context, source)) {
          final childRelativePath = Path(
            child.path.segments.skip(source.segments.length).toList(),
          );
          final childDestination = Path([
            ...destination.segments,
            ...childRelativePath.segments,
          ]);
          await copy(context, child.path, childDestination, options: options);
        }
      }
    } else {
      // 复制文件
      await nonRecursiveCopyFile(
        context,
        source,
        destination,
        options: options,
      );
    }
  }

  Future<void> nonRecursiveCreateDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    context.logger.log(
      Level.debug,
      '创建目录',
      metadata: {'path': path.toString(), 'operation': 'create_directory'},
    );
    // 先寻找到path的父目录
    final parentDir = path.parent;
    if (parentDir == null) {
      context.logger.log(
        Level.warning,
        '无法创建目录：无父路径',
        metadata: {
          'path': path.toString(),
          'operation': 'cannot_create_directory_no_parent',
        },
      );
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(context, parentDir);
    // 如果父目录不存在，报错
    if (parentEntity == null) {
      context.logger.log(
        Level.warning,
        '父目录未找到',
        metadata: {
          'parent_dir': parentDir.toString(),
          'operation': 'parent_directory_not_found',
        },
      );
      throw FileSystemException.notFound(parentDir);
    }
    // 如果父目录不是目录，报错
    if (!parentEntity.status.isDirectory) {
      context.logger.log(
        Level.warning,
        '父路径不是目录',
        metadata: {
          'parent_dir': parentDir.toString(),
          'operation': 'parent_not_directory',
        },
      );
      throw FileSystemException.notADirectory(parentDir);
    }

    final dirName = path.filename!;
    // 检查是否已存在
    if (parentEntity.children!.containsKey(dirName)) {
      context.logger.log(
        Level.warning,
        '目录已存在',
        metadata: {
          'path': path.toString(),
          'operation': 'directory_already_exists',
        },
      );
      throw FileSystemException.alreadyExists(path);
    }

    // 直接创建
    final newDir = _MemoryFileEntity(
      FileStatus(path: path, isDirectory: true),
      children: <String, _MemoryFileEntity>{},
    );
    parentEntity.children![dirName] = newDir;
    context.logger.log(
      Level.debug,
      '目录创建成功',
      metadata: {
        'path': path.toString(),
        'operation': 'directory_created_successfully',
      },
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    if (!options.createParents) {
      await nonRecursiveCreateDirectory(context, path, options: options);
      return;
    }

    // 递归创建父目录
    final parents = <Path>[];
    Path? current = path;
    while (current != null && !await exists(context, current)) {
      parents.add(current);
      current = current.parent;
    }

    // 从最顶层开始创建
    for (final parent in parents.reversed) {
      try {
        await nonRecursiveCreateDirectory(
          context,
          parent,
          options: const CreateDirectoryOptions(createParents: false),
        );
      } on FileSystemException catch (e) {
        if (e.code != FileSystemErrorCode.alreadyExists) {
          rethrow;
        }
      }
    }
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '删除文件',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'delete_file',
      },
    );
    // 寻找文件或目录
    final entity = _getEntity(context, path);
    if (entity == null) {
      logger.warning(
        '删除失败：实体未找到',
        metadata: {
          'path': path.toString(),
          'operation': 'delete_failed_entity_not_found',
        },
      );
      throw FileSystemException.notFound(path);
    }
    // 如果是目录，检查是否为空
    if (entity.status.isDirectory &&
        entity.children!.isNotEmpty &&
        !options.recursive) {
      logger.warning(
        '删除失败：目录非空',
        metadata: {
          'path': path.toString(),
          'operation': 'delete_failed_directory_not_empty',
        },
      );
      throw FileSystemException.notEmptyDirectory(path);
    }
    // 从父目录中删除
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning(
        '删除失败：无父路径',
        metadata: {
          'path': path.toString(),
          'operation': 'delete_failed_no_parent_path',
        },
      );
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(context, parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        '删除失败：父目录未找到或不是目录',
        metadata: {
          'path': path.toString(),
          'parent_path': parentPath.toString(),
          'operation': 'delete_failed_parent_not_found_or_not_directory',
        },
      );
      throw FileSystemException.notADirectory(parentPath);
    }

    final fileName = path.filename!;
    final removed = parentEntity.children!.remove(fileName);
    if (removed != null) {
      logger.debug(
        '删除成功',
        metadata: {'path': path.toString(), 'operation': 'delete_successful'},
      );
    } else {
      logger.warning(
        '删除失败：在父目录中未找到文件',
        metadata: {
          'path': path.toString(),
          'operation': 'delete_failed_file_not_found_in_parent',
        },
      );
    }
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    final logger = context.logger;
    logger.debug(
      '打开读取流',
      metadata: {
        'path': path.toString(),
        'start': options.start,
        'end': options.end,
        'operation': 'open_read_stream',
      },
    );
    _readOperations++;

    await preOpenReadCheck(context, path, options: options);
    final entity = _getEntity(context, path);
    assert(entity != null, 'File not found: $path');
    assert(!entity!.status.isDirectory, 'Cannot read a directory: $path');
    final content = entity!.content!;

    final start = options.start ?? 0;
    final end = options.end ?? content.length;
    final readSize = end - start;
    _totalBytesRead += readSize;

    logger.debug(
      '读取字节数据',
      metadata: {
        'path': path.toString(),
        'read_size': readSize,
        'start': start,
        'end': end,
        'operation': 'reading_bytes',
      },
    );
    yield content.sublist(start, end);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '打开写入流',
      metadata: {
        'path': path.toString(),
        'mode': options.mode.toString(),
        'operation': 'open_write_stream',
      },
    );
    // 预检查所有
    await preOpenWriteCheck(context, path, options: options);
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning(
        '写入失败：无父路径',
        metadata: {
          'path': path.toString(),
          'operation': 'write_failed_no_parent_path',
        },
      );
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(context, parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        '写入失败：父目录未找到或不是目录',
        metadata: {
          'path': path.toString(),
          'parent_path': parentPath.toString(),
          'operation': 'write_failed_parent_not_found_or_not_directory',
        },
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
      logger.debug(
        '追加到现有文件',
        metadata: {
          'path': path.toString(),
          'existing_size': existingEntity.content!.length,
          'operation': 'append_to_existing_file',
        },
      );
    } else {
      logger.debug(
        '创建新文件或覆盖',
        metadata: {
          'path': path.toString(),
          'is_overwrite': existingEntity != null,
          'operation': 'create_new_or_overwrite_file',
        },
      );
    }

    parentEntity.children![fileName] = newEntity; // 添加新文件

    // 返回一个优化的Sink来写入数据
    final controller = StreamController<List<int>>();
    controller.stream.listen(
      (data) {
        logger.trace(
          '写入数据块',
          metadata: {
            'path': path.toString(),
            'bytes_written': data.length,
            'operation': 'writing_data_chunk',
          },
        );
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

        logger.debug(
          '写入完成',
          metadata: {
            'path': path.toString(),
            'final_size': newEntity.content?.length ?? 0,
            'buffer_size_before_flush': bufferSizeBeforeFlush,
            'operation': 'write_completed',
          },
        );
        controller.close();
      },
      onError: (Object error, StackTrace? stackTrace) {
        logger.warning(
          '写入错误',
          metadata: {
            'path': path.toString(),
            'error': error.toString(),
            'operation': 'write_error',
          },
        );
        controller.addError(error, stackTrace);
      },
    );
    return controller.sink;
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '获取文件状态',
      metadata: {'path': path.toString(), 'operation': 'get_file_status'},
    );
    final entity = _getEntity(context, path);
    if (entity == null) {
      logger.debug(
        '文件状态未找到',
        metadata: {
          'path': path.toString(),
          'operation': 'file_status_not_found',
        },
      );
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

    logger.debug(
      '文件状态获取成功',
      metadata: {
        'path': path.toString(),
        'is_directory': entity.status.isDirectory,
        'size': entity.status.size,
        'operation': 'file_status_found',
      },
    );
    return entity.status;
  }

  /// 批量写入文件的优化方法，避免Stream的开销
  Future<void> writeBytesDirect(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '直接写入字节数据',
      metadata: {
        'path': path.toString(),
        'data_size': data.length,
        'mode': options.mode.toString(),
        'operation': 'direct_write_bytes',
      },
    );

    // 预检查
    await preOpenWriteCheck(context, path, options: options);
    final parentPath = path.parent;
    if (parentPath == null) {
      logger.warning(
        '写入失败：无父路径',
        metadata: {
          'path': path.toString(),
          'operation': 'write_failed_no_parent_path',
        },
      );
      throw FileSystemException.notFound(path);
    }
    final parentEntity = _getEntity(context, parentPath);
    if (parentEntity == null || !parentEntity.status.isDirectory) {
      logger.warning(
        '写入失败：父目录未找到或不是目录',
        metadata: {
          'path': path.toString(),
          'parent_path': parentPath.toString(),
          'operation': 'write_failed_parent_not_found_or_not_directory',
        },
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
      logger.debug(
        '追加到现有文件',
        metadata: {
          'path': path.toString(),
          'new_size': newEntity.content!.length,
          'appended_bytes': data.length,
          'operation': 'appended_to_existing_file',
        },
      );
    } else {
      // 覆盖或新建模式
      newEntity.content = data;
      logger.debug(
        '创建或覆盖文件',
        metadata: {
          'path': path.toString(),
          'size': data.length,
          'is_overwrite': existingEntity != null,
          'operation': 'created_or_overwrote_file',
        },
      );
    }

    parentEntity.children![fileName] = newEntity;

    // 更新统计
    _writeOperations++;
    _totalBytesWritten += data.length;

    logger.debug(
      '直接写入完成',
      metadata: {
        'path': path.toString(),
        'bytes_written': data.length,
        'operation': 'direct_write_completed',
      },
    );
  }

  /// 高效的文件拷贝方法，直接操作内存
  Future<void> copyDirect(
    Context context,
    Path source,
    Path destination, {
    bool overwrite = false,
  }) async {
    final logger = context.logger;
    logger.debug(
      '直接复制文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': overwrite,
        'operation': 'direct_copy_file',
      },
    );

    final sourceEntity = _getEntity(context, source);
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
      context,
      destination,
      sourceEntity.content!,
      options: WriteOptions(
        mode: overwrite ? WriteMode.overwrite : WriteMode.write,
      ),
    );

    logger.debug(
      '直接复制完成',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'bytes_copied': sourceEntity.content!.length,
        'operation': 'direct_copy_completed',
      },
    );
  }
}
