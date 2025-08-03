import 'dart:async';
import 'dart:typed_data';
import '../abstract/index.dart';

class UnionFileSystemItem {
  const UnionFileSystemItem({
    required this.fileSystem,
    required this.mountPath,
    this.readOnly = false,
    this.priority = 0,
  });

  final IFileSystem fileSystem;
  final Path mountPath;
  final bool readOnly;
  final int priority;
}

class UnionFileSystem extends IFileSystem {
  UnionFileSystem({required List<UnionFileSystemItem> items})
    : _items = List.from(items)
        ..sort((a, b) => b.priority.compareTo(a.priority));
  final List<UnionFileSystemItem> _items;

  /// 获取路径对应的文件系统项，按优先级排序
  List<UnionFileSystemItem> _getItemsForPath(Context context, Path path) {
    final logger = context.logger;
    final items = _items.where((item) {
      // 检查路径是否在该文件系统的挂载点下
      return _isPathUnder(path, item.mountPath);
    }).toList();

    logger.trace(
      '查找路径的文件系统项',
      metadata: {
        'path': path.toString(),
        'found_items': items.length,
        'operation': 'get_items_for_path',
      },
    );
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      logger.trace(
        '文件系统项详情',
        metadata: {
          'index': i,
          'mount_path': item.mountPath.toString(),
          'priority': item.priority,
          'read_only': item.readOnly,
          'operation': 'filesystem_item_details',
        },
      );
    }

    return items;
  }

  /// 检查路径是否在指定的挂载点下
  bool _isPathUnder(Path path, Path mountPath) {
    if (mountPath.isRoot) return true;
    if (path.segments.length < mountPath.segments.length) return false;

    for (int i = 0; i < mountPath.segments.length; i++) {
      if (path.segments[i] != mountPath.segments[i]) return false;
    }
    return true;
  }

  /// 将union路径转换为文件系统内部路径
  Path _convertPath(Context context, Path unionPath, Path mountPath) {
    final logger = context.logger;

    if (mountPath.isRoot) return unionPath;

    // 移除挂载点前缀
    final segments = unionPath.segments.sublist(mountPath.segments.length);
    final ret = Path(segments);
    logger.trace(
      '转换路径',
      metadata: {
        'union_path': unionPath.toString(),
        'mount_path': mountPath.toString(),
        'internal_path': ret.toString(),
        'operation': 'convert_path',
      },
    );
    return ret;
  }

  /// 获取第一个包含指定路径文件的可读文件系统项（异步版本）
  Future<UnionFileSystemItem?> _getFirstReadableItemAsync(
    Context context,
    Path path,
  ) async {
    final logger = context.logger;
    logger.debug(
      '搜索可读文件系统项',
      metadata: {'path': path.toString(), 'operation': 'search_readable_item'},
    );
    final items = _getItemsForPath(context, path);

    // 按挂载点的具体程度排序（路径段数更多的更具体），然后按优先级排序
    items.sort((a, b) {
      final mountLengthCompare = b.mountPath.segments.length.compareTo(
        a.mountPath.segments.length,
      );
      if (mountLengthCompare != 0) return mountLengthCompare;
      return b.priority.compareTo(a.priority);
    });

    for (final item in items) {
      final internalPath = _convertPath(context, path, item.mountPath);
      logger.trace(
        '检查文件系统中的存在性',
        metadata: {
          'mount_path': item.mountPath.toString(),
          'internal_path': internalPath.toString(),
          'operation': 'check_existence_in_filesystem',
        },
      );

      if (await item.fileSystem.exists(context, internalPath)) {
        logger.debug(
          '找到可读文件系统项',
          metadata: {
            'path': path.toString(),
            'mount_path': item.mountPath.toString(),
            'operation': 'found_readable_item',
          },
        );
        return item;
      }
    }

    logger.debug(
      '未找到可读文件系统项',
      metadata: {
        'path': path.toString(),
        'operation': 'no_readable_item_found',
      },
    );
    return null;
  }

  /// 获取第一个可写的文件系统项，优先选择最具体的挂载点
  UnionFileSystemItem? _getFirstWritableItem(Context context, Path path) {
    final logger = context.logger;
    logger.debug(
      '搜索可写文件系统项',
      metadata: {'path': path.toString(), 'operation': 'search_writable_item'},
    );
    final items = _getItemsForPath(
      context,
      path,
    ).where((item) => !item.readOnly).toList();

    if (items.isEmpty) {
      logger.warning(
        '未找到可写文件系统',
        metadata: {
          'path': path.toString(),
          'operation': 'no_writable_filesystem_found',
        },
      );
      return null;
    }

    // 按挂载点的具体程度排序（路径段数更多的更具体），然后按优先级排序
    items.sort((a, b) {
      final mountLengthCompare = b.mountPath.segments.length.compareTo(
        a.mountPath.segments.length,
      );
      if (mountLengthCompare != 0) return mountLengthCompare;
      return b.priority.compareTo(a.priority);
    });

    final selected = items.first;
    logger.debug(
      '选择可写文件系统',
      metadata: {
        'path': path.toString(),
        'selected_mount_path': selected.mountPath.toString(),
        'priority': selected.priority,
        'operation': 'selected_writable_filesystem',
      },
    );
    return selected;
  }

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    final logger = context.logger;
    logger.info(
      '复制文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': options.overwrite,
        'recursive': options.recursive,
        'operation': 'copy_file',
      },
    );

    final sourceItem = await _getFirstReadableItemAsync(context, source);
    final destItem = _getFirstWritableItem(context, destination);

    if (sourceItem == null) {
      logger.warning(
        '复制失败：源文件未找到',
        metadata: {
          'source': source.toString(),
          'operation': 'copy_failed_source_not_found',
        },
      );
      throw FileSystemException.notFound(source);
    }
    if (destItem == null) {
      logger.warning(
        '复制失败：目标位置无可写文件系统',
        metadata: {
          'destination': destination.toString(),
          'operation': 'copy_failed_no_writable_destination',
        },
      );
      throw FileSystemException.readOnly(destination);
    }

    final sourceInternalPath = _convertPath(
      context,
      source,
      sourceItem.mountPath,
    );
    final destInternalPath = _convertPath(
      context,
      destination,
      destItem.mountPath,
    );

    // 如果源和目标在同一个文件系统中，直接拷贝
    if (sourceItem == destItem) {
      logger.debug(
        '同文件系统内直接复制',
        metadata: {
          'mount_path': sourceItem.mountPath.toString(),
          'operation': 'direct_copy_same_filesystem',
        },
      );
      return sourceItem.fileSystem.copy(
        context,
        sourceInternalPath,
        destInternalPath,
        options: options,
      );
    }

    logger.debug(
      '跨文件系统复制',
      metadata: {
        'source_mount': sourceItem.mountPath.toString(),
        'dest_mount': destItem.mountPath.toString(),
        'operation': 'cross_filesystem_copy',
      },
    );

    // 否则通过读写实现跨文件系统拷贝
    final sourceStatus = await sourceItem.fileSystem.stat(
      context,
      sourceInternalPath,
    );
    if (sourceStatus == null) {
      logger.warning(
        '复制失败：源文件状态未找到',
        metadata: {
          'source': source.toString(),
          'operation': 'copy_failed_source_status_not_found',
        },
      );
      throw FileSystemException.notFound(source);
    }

    if (sourceStatus.isDirectory) {
      logger.debug(
        '复制目录',
        metadata: {'source': source.toString(), 'operation': 'copy_directory'},
      );
      // 拷贝目录
      await destItem.fileSystem.createDirectory(context, destInternalPath);

      if (options.recursive) {
        logger.debug(
          '递归复制目录内容',
          metadata: {
            'source': source.toString(),
            'operation': 'recursive_copy_directory_contents',
          },
        );
        await for (final item in sourceItem.fileSystem.list(
          context,
          sourceInternalPath,
          options: const ListOptions(recursive: true),
        )) {
          final relativePath = Path(
            item.path.segments
                .skip(sourceInternalPath.segments.length)
                .toList(),
          );
          final srcPath = Path([...source.segments, ...relativePath.segments]);
          final dstPath = Path([
            ...destination.segments,
            ...relativePath.segments,
          ]);
          await copy(context, srcPath, dstPath, options: options);
        }
      }
    } else {
      logger.debug(
        '复制文件',
        metadata: {
          'source': source.toString(),
          'size_bytes': sourceStatus.size,
          'operation': 'copy_file',
        },
      );
      // 拷贝文件
      final data = await sourceItem.fileSystem.readAsBytes(
        context,
        sourceInternalPath,
      );
      await destItem.fileSystem.writeBytes(
        context,
        destInternalPath,
        data,
        options: WriteOptions(
          mode: options.overwrite ? WriteMode.overwrite : WriteMode.write,
        ),
      );
    }

    logger.info(
      '复制完成',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'operation': 'copy_completed',
      },
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    final logger = context.logger;
    logger.info(
      '创建目录',
      metadata: {
        'path': path.toString(),
        'create_parents': options.createParents,
        'operation': 'create_directory',
      },
    );

    final item = _getFirstWritableItem(context, path);
    if (item == null) {
      logger.warning(
        '创建目录失败：无可写文件系统',
        metadata: {
          'path': path.toString(),
          'operation': 'create_directory_failed_no_writable_filesystem',
        },
      );
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(context, path, item.mountPath);
    logger.debug(
      '在文件系统中创建目录',
      metadata: {
        'mount_path': item.mountPath.toString(),
        'internal_path': internalPath.toString(),
        'operation': 'create_directory_in_filesystem',
      },
    );

    await item.fileSystem.createDirectory(
      context,
      internalPath,
      options: options,
    );
    logger.info(
      '目录创建成功',
      metadata: {
        'path': path.toString(),
        'operation': 'directory_created_successfully',
      },
    );
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final logger = context.logger;
    logger.info(
      '删除文件',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'delete_file',
      },
    );

    final items = _getItemsForPath(
      context,
      path,
    ).where((item) => !item.readOnly).toList();

    if (items.isEmpty) {
      logger.warning(
        '删除失败：无可写文件系统',
        metadata: {
          'path': path.toString(),
          'operation': 'delete_failed_no_writable_filesystem',
        },
      );
      throw FileSystemException.readOnly(path);
    }

    // 尝试从所有可写的文件系统中删除
    bool deleted = false;
    int attemptCount = 0;

    for (final item in items) {
      final internalPath = _convertPath(context, path, item.mountPath);
      attemptCount++;

      try {
        if (await item.fileSystem.exists(context, internalPath)) {
          logger.debug(
            '从文件系统中删除',
            metadata: {
              'mount_path': item.mountPath.toString(),
              'internal_path': internalPath.toString(),
              'operation': 'delete_from_filesystem',
            },
          );
          await item.fileSystem.delete(context, internalPath, options: options);
          deleted = true;
          logger.debug(
            '从文件系统删除成功',
            metadata: {
              'mount_path': item.mountPath.toString(),
              'operation': 'delete_from_filesystem_success',
            },
          );
        } else {
          logger.trace(
            '文件系统中路径不存在',
            metadata: {
              'mount_path': item.mountPath.toString(),
              'internal_path': internalPath.toString(),
              'operation': 'path_not_exist_in_filesystem',
            },
          );
        }
      } catch (e) {
        // 忽略删除错误，继续尝试其他文件系统
        logger.warning(
          '从文件系统删除失败',
          metadata: {
            'mount_path': item.mountPath.toString(),
            'internal_path': internalPath.toString(),
            'error': e.toString(),
            'operation': 'delete_from_filesystem_failed',
          },
        );
        continue;
      }
    }

    if (!deleted) {
      logger.warning(
        '删除失败：在任何文件系统中都未找到路径',
        metadata: {
          'path': path.toString(),
          'attempted_filesystems': attemptCount,
          'operation': 'delete_failed_path_not_found',
        },
      );
      throw FileSystemException.notFound(path);
    }

    logger.info(
      '删除完成',
      metadata: {'path': path.toString(), 'operation': 'delete_completed'},
    );
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    final logger = context.logger;
    // 特殊处理根目录：如果没有文件系统挂载在根目录，
    // 但有挂载点是根目录的子目录，则根目录应该存在
    if (path.isRoot) {
      final items = _getItemsForPath(context, path);

      // 如果有文件系统挂载在根目录，检查实际存在性
      for (final item in items) {
        if (item.mountPath.isRoot) {
          if (await item.fileSystem.exists(context, path, options: options)) {
            return true;
          }
        }
      }

      // 否则检查是否有任何挂载点在根目录下，如果有则根目录存在
      final hasChildMounts = _items.any(
        (item) => !item.mountPath.isRoot && item.mountPath.segments.isNotEmpty,
      );

      if (hasChildMounts) {
        logger.debug(
          '根目录因子挂载点而存在',
          metadata: {'operation': 'root_directory_exists_due_to_child_mounts'},
        );
        return true;
      }

      // 如果没有任何挂载点，根目录不存在
      return false;
    }

    // 对于非根目录路径，使用原有逻辑
    final items = _getItemsForPath(context, path);

    for (final item in items) {
      final internalPath = _convertPath(context, path, item.mountPath);
      if (await item.fileSystem.exists(
        context,
        internalPath,
        options: options,
      )) {
        return true;
      }
    }

    return false;
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final logger = context.logger;
    final seenPaths = <String>{};

    // 首先添加所有挂载点（如果它们是当前路径的直接子目录）
    for (final item in _items) {
      if (!item.mountPath.isRoot) {
        // 检查挂载点是否是当前路径的直接子项
        if (item.mountPath.segments.length == path.segments.length + 1) {
          bool isChildOfPath = true;
          for (int i = 0; i < path.segments.length; i++) {
            if (path.segments[i] != item.mountPath.segments[i]) {
              isChildOfPath = false;
              break;
            }
          }

          if (isChildOfPath) {
            final mountPointName = item.mountPath.segments.last;
            final mountPointPath = Path([...path.segments, mountPointName]);
            final pathKey = mountPointPath.toString();

            if (!seenPaths.contains(pathKey)) {
              seenPaths.add(pathKey);
              yield FileStatus(
                path: mountPointPath,
                isDirectory: true,
                size: null,
                mimeType: null,
              );
            }
          }
        }
      }
    }

    // 然后列出实际的文件系统内容
    final items = _getItemsForPath(context, path);

    for (final item in items) {
      final internalPath = _convertPath(context, path, item.mountPath);

      try {
        await for (final status in item.fileSystem.list(
          context,
          internalPath,
          options: options,
        )) {
          // 将内部路径转换回union路径
          final unionPath = Path([
            ...path.segments,
            ...status.path.segments.skip(internalPath.segments.length),
          ]);
          final pathKey = unionPath.toString();

          // 避免重复项目（高优先级的会先出现）
          if (!seenPaths.contains(pathKey)) {
            seenPaths.add(pathKey);
            yield FileStatus(
              path: unionPath,
              isDirectory: status.isDirectory,
              size: status.size,
              mimeType: status.mimeType,
            );
          }
        }
      } catch (e) {
        // 忽略单个文件系统的列表错误
        logger.warning(
          '目录列表失败',
          metadata: {
            'internal_path': internalPath.toString(),
            'error': e.toString(),
            'operation': 'list_directory_failed',
          },
        );
        continue;
      }
    }
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    final logger = context.logger;
    logger.info(
      '移动文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': options.overwrite,
        'recursive': options.recursive,
        'operation': 'move_file',
      },
    );

    final sourceItem = await _getFirstReadableItemAsync(context, source);
    final destItem = _getFirstWritableItem(context, destination);

    if (sourceItem == null) {
      logger.warning(
        '移动失败：源文件未找到',
        metadata: {
          'source': source.toString(),
          'operation': 'move_failed_source_not_found',
        },
      );
      throw FileSystemException.notFound(source);
    }
    if (destItem == null) {
      logger.warning(
        '移动失败：目标位置无可写文件系统',
        metadata: {
          'destination': destination.toString(),
          'operation': 'move_failed_no_writable_destination',
        },
      );
      throw FileSystemException.readOnly(destination);
    }
    if (sourceItem.readOnly) {
      logger.warning(
        '移动失败：源文件系统为只读',
        metadata: {
          'source': source.toString(),
          'operation': 'move_failed_source_readonly',
        },
      );
      throw FileSystemException.readOnly(source);
    }

    final sourceInternalPath = _convertPath(
      context,
      source,
      sourceItem.mountPath,
    );
    final destInternalPath = _convertPath(
      context,
      destination,
      destItem.mountPath,
    );

    // 如果源和目标在同一个文件系统中，直接移动
    if (sourceItem == destItem) {
      logger.debug(
        '同文件系统内直接移动',
        metadata: {
          'mount_path': sourceItem.mountPath.toString(),
          'operation': 'direct_move_same_filesystem',
        },
      );
      await sourceItem.fileSystem.move(
        context,
        sourceInternalPath,
        destInternalPath,
        options: options,
      );
    } else {
      logger.debug(
        '跨文件系统移动',
        metadata: {
          'source_mount': sourceItem.mountPath.toString(),
          'dest_mount': destItem.mountPath.toString(),
          'operation': 'cross_filesystem_move',
        },
      );

      // 否则通过拷贝+删除实现跨文件系统移动
      await copy(
        context,
        source,
        destination,
        options: CopyOptions(
          overwrite: options.overwrite,
          recursive: options.recursive,
        ),
      );

      await delete(
        context,
        source,
        options: DeleteOptions(recursive: options.recursive),
      );
    }

    logger.info(
      '移动完成',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'operation': 'move_completed',
      },
    );
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

    final item = await _getFirstReadableItemAsync(context, path);
    if (item == null) {
      logger.warning(
        '打开读取失败：文件未找到',
        metadata: {
          'path': path.toString(),
          'operation': 'open_read_failed_file_not_found',
        },
      );
      yield* Stream.error(FileSystemException.notFound(path));
      return;
    }

    final internalPath = _convertPath(context, path, item.mountPath);
    logger.debug(
      '从文件系统读取',
      metadata: {
        'mount_path': item.mountPath.toString(),
        'internal_path': internalPath.toString(),
        'operation': 'read_from_filesystem',
      },
    );

    yield* item.fileSystem.openRead(context, internalPath, options: options);
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

    final item = _getFirstWritableItem(context, path);
    if (item == null) {
      logger.warning(
        '打开写入失败：无可写文件系统',
        metadata: {
          'path': path.toString(),
          'operation': 'open_write_failed_no_writable_filesystem',
        },
      );
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(context, path, item.mountPath);
    logger.debug(
      '写入到文件系统',
      metadata: {
        'mount_path': item.mountPath.toString(),
        'internal_path': internalPath.toString(),
        'operation': 'write_to_filesystem',
      },
    );

    return item.fileSystem.openWrite(context, internalPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '读取字节数据',
      metadata: {
        'path': path.toString(),
        'start': options.start,
        'end': options.end,
        'operation': 'read_as_bytes',
      },
    );

    final item = await _getFirstReadableItemAsync(context, path);
    if (item == null) {
      logger.warning(
        '读取字节失败：文件未找到',
        metadata: {
          'path': path.toString(),
          'operation': 'read_bytes_failed_file_not_found',
        },
      );
      throw FileSystemException.notFound(path);
    }

    final internalPath = _convertPath(context, path, item.mountPath);
    logger.debug(
      '从文件系统读取字节',
      metadata: {
        'mount_path': item.mountPath.toString(),
        'internal_path': internalPath.toString(),
        'operation': 'read_bytes_from_filesystem',
      },
    );

    final data = await item.fileSystem.readAsBytes(
      context,
      internalPath,
      options: options,
    );
    logger.debug(
      '读取字节完成',
      metadata: {
        'path': path.toString(),
        'bytes_read': data.length,
        'operation': 'read_bytes_completed',
      },
    );
    return data;
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final logger = context.logger;
    // 特殊处理根目录：如果没有文件系统挂载在根目录，
    // 但有挂载点是根目录的子目录，则根目录应该显示为虚拟目录
    if (path.isRoot) {
      final items = _getItemsForPath(context, path);

      // 如果有文件系统挂载在根目录，使用实际的stat结果
      for (final item in items) {
        if (item.mountPath.isRoot) {
          final status = await item.fileSystem.stat(
            context,
            path,
            options: options,
          );
          if (status != null) {
            return FileStatus(
              path: path,
              isDirectory: status.isDirectory,
              size: status.size,
              mimeType: status.mimeType,
            );
          }
        }
      }

      // 否则检查是否有任何挂载点在根目录下，如果有则返回虚拟目录状态
      final hasChildMounts = _items.any(
        (item) => !item.mountPath.isRoot && item.mountPath.segments.isNotEmpty,
      );

      if (hasChildMounts) {
        logger.debug(
          '返回虚拟根目录状态',
          metadata: {'operation': 'return_virtual_root_directory_status'},
        );
        return FileStatus(
          path: path,
          isDirectory: true,
          size: null,
          mimeType: null,
        );
      }

      // 如果没有任何挂载点，返回null
      return null;
    }

    // 对于非根目录路径，使用原有逻辑
    final items = _getItemsForPath(context, path);

    for (final item in items) {
      final internalPath = _convertPath(context, path, item.mountPath);
      final status = await item.fileSystem.stat(
        context,
        internalPath,
        options: options,
      );
      if (status != null) {
        // 将内部路径转换回union路径
        return FileStatus(
          path: path,
          isDirectory: status.isDirectory,
          size: status.size,
          mimeType: status.mimeType,
        );
      }
    }

    return null;
  }

  @override
  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '写入字节数据',
      metadata: {
        'path': path.toString(),
        'data_length': data.length,
        'mode': options.mode.toString(),
        'operation': 'write_bytes',
      },
    );

    final item = _getFirstWritableItem(context, path);
    if (item == null) {
      logger.warning(
        '写入字节失败：无可写文件系统',
        metadata: {
          'path': path.toString(),
          'operation': 'write_bytes_failed_no_writable_filesystem',
        },
      );
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(context, path, item.mountPath);
    logger.debug(
      '写入字节到文件系统',
      metadata: {
        'mount_path': item.mountPath.toString(),
        'internal_path': internalPath.toString(),
        'operation': 'write_bytes_to_filesystem',
      },
    );

    await item.fileSystem.writeBytes(
      context,
      internalPath,
      data,
      options: options,
    );
    logger.debug(
      '字节写入成功',
      metadata: {
        'path': path.toString(),
        'bytes_written': data.length,
        'operation': 'write_bytes_success',
      },
    );
  }
}
