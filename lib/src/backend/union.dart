import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

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
  UnionFileSystem({
    required List<UnionFileSystemItem> items,
    String loggerName = 'UnionFileSystem',
  }) : _items = List.from(items)
         ..sort((a, b) => b.priority.compareTo(a.priority)),
       logger = Logger(loggerName);

  @override
  final Logger logger;
  final List<UnionFileSystemItem> _items;

  /// 获取路径对应的文件系统项，按优先级排序
  List<UnionFileSystemItem> _getItemsForPath(Path path) {
    final items = _items.where((item) {
      // 检查路径是否在该文件系统的挂载点下
      return _isPathUnder(path, item.mountPath);
    }).toList();

    logger.finest('Found ${items.length} filesystem items for path: $path');
    for (final item in items) {
      logger.finest(
        '  - Mount: ${item.mountPath}, '
        'Priority: ${item.priority}, '
        'ReadOnly: ${item.readOnly}',
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
  Path _convertPath(Path unionPath, Path mountPath) {
    if (mountPath.isRoot) return unionPath;

    // 移除挂载点前缀
    final segments = unionPath.segments.sublist(mountPath.segments.length);
    final ret = Path(segments);
    logger.finest('Convert path: $unionPath -> $ret (mount: $mountPath)');
    return ret;
  }

  /// 获取第一个包含指定路径文件的可读文件系统项（异步版本）
  Future<UnionFileSystemItem?> _getFirstReadableItemAsync(Path path) async {
    logger.fine('Searching for readable item for path: $path');
    final items = _getItemsForPath(path);

    // 按挂载点的具体程度排序（路径段数更多的更具体），然后按优先级排序
    items.sort((a, b) {
      final mountLengthCompare = b.mountPath.segments.length.compareTo(
        a.mountPath.segments.length,
      );
      if (mountLengthCompare != 0) return mountLengthCompare;
      return b.priority.compareTo(a.priority);
    });

    for (final item in items) {
      final internalPath = _convertPath(path, item.mountPath);
      logger.finest(
        'Checking existence in filesystem: ${item.mountPath} -> $internalPath',
      );

      if (await item.fileSystem.exists(internalPath)) {
        logger.fine(
          'Found readable item for $path in filesystem: ${item.mountPath}',
        );
        return item;
      }
    }

    logger.fine('No readable item found for path: $path');
    return null;
  }

  /// 获取第一个可写的文件系统项，优先选择最具体的挂载点
  UnionFileSystemItem? _getFirstWritableItem(Path path) {
    logger.fine('Searching for writable item for path: $path');
    final items = _getItemsForPath(
      path,
    ).where((item) => !item.readOnly).toList();

    if (items.isEmpty) {
      logger.warning('No writable filesystem found for path: $path');
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
    logger.fine(
      'Selected writable filesystem for $path: ${selected.mountPath} '
      '(priority: ${selected.priority})',
    );
    return selected;
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    logger.info(
      'Copying from $source to $destination (overwrite: ${options.overwrite}, '
      'recursive: ${options.recursive})',
    );

    final sourceItem = await _getFirstReadableItemAsync(source);
    final destItem = _getFirstWritableItem(destination);

    if (sourceItem == null) {
      logger.warning('Copy failed: source not found: $source');
      throw FileSystemException.notFound(source);
    }
    if (destItem == null) {
      logger.warning(
        'Copy failed: no writable filesystem for destination: $destination',
      );
      throw FileSystemException.readOnly(destination);
    }

    final sourceInternalPath = _convertPath(source, sourceItem.mountPath);
    final destInternalPath = _convertPath(destination, destItem.mountPath);

    // 如果源和目标在同一个文件系统中，直接拷贝
    if (sourceItem == destItem) {
      logger.fine(
        'Direct copy within same filesystem: ${sourceItem.mountPath}',
      );
      return sourceItem.fileSystem.copy(
        sourceInternalPath,
        destInternalPath,
        options: options,
      );
    }

    logger.fine(
      'Cross-filesystem copy: ${sourceItem.mountPath} -> ${destItem.mountPath}',
    );

    // 否则通过读写实现跨文件系统拷贝
    final sourceStatus = await sourceItem.fileSystem.stat(sourceInternalPath);
    if (sourceStatus == null) {
      logger.warning('Copy failed: source status not found: $source');
      throw FileSystemException.notFound(source);
    }

    if (sourceStatus.isDirectory) {
      logger.fine('Copying directory: $source');
      // 拷贝目录
      await destItem.fileSystem.createDirectory(destInternalPath);

      if (options.recursive) {
        logger.fine('Recursively copying directory contents');
        await for (final item in sourceItem.fileSystem.list(
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
          await copy(srcPath, dstPath, options: options);
        }
      }
    } else {
      logger.fine('Copying file: $source (size: ${sourceStatus.size} bytes)');
      // 拷贝文件
      final data = await sourceItem.fileSystem.readAsBytes(sourceInternalPath);
      await destItem.fileSystem.writeBytes(
        destInternalPath,
        data,
        options: WriteOptions(
          mode: options.overwrite ? WriteMode.overwrite : WriteMode.write,
        ),
      );
    }

    logger.info('Copy completed: $source -> $destination');
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    logger.info(
      'Creating directory: $path (createParents: ${options.createParents})',
    );

    final item = _getFirstWritableItem(path);
    if (item == null) {
      logger.warning(
        'Create directory failed: no writable filesystem for path: $path',
      );
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(path, item.mountPath);
    logger.fine(
      'Creating directory in filesystem ${item.mountPath}: $internalPath',
    );

    await item.fileSystem.createDirectory(internalPath, options: options);
    logger.info('Directory created successfully: $path');
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    logger.info('Deleting: $path (recursive: ${options.recursive})');

    final items = _getItemsForPath(
      path,
    ).where((item) => !item.readOnly).toList();

    if (items.isEmpty) {
      logger.warning('Delete failed: no writable filesystem for path: $path');
      throw FileSystemException.readOnly(path);
    }

    // 尝试从所有可写的文件系统中删除
    bool deleted = false;
    int attemptCount = 0;

    for (final item in items) {
      final internalPath = _convertPath(path, item.mountPath);
      attemptCount++;

      try {
        if (await item.fileSystem.exists(internalPath)) {
          logger.fine(
            'Deleting from filesystem ${item.mountPath}: $internalPath',
          );
          await item.fileSystem.delete(internalPath, options: options);
          deleted = true;
          logger.fine(
            'Successfully deleted from filesystem: ${item.mountPath}',
          );
        } else {
          logger.finest(
            'Path does not exist in filesystem '
            '${item.mountPath}: $internalPath',
          );
        }
      } catch (e) {
        // 忽略删除错误，继续尝试其他文件系统
        logger.warning(
          'Failed to delete $internalPath from '
          'filesystem ${item.mountPath}: $e',
        );
        continue;
      }
    }

    if (!deleted) {
      logger.warning(
        'Delete failed: path not found in any filesystem: $path '
        '(attempted $attemptCount filesystems)',
      );
      throw FileSystemException.notFound(path);
    }

    logger.info('Delete completed: $path');
  }

  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    final items = _getItemsForPath(path);

    for (final item in items) {
      final internalPath = _convertPath(path, item.mountPath);
      if (await item.fileSystem.exists(internalPath, options: options)) {
        return true;
      }
    }

    return false;
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
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
    final items = _getItemsForPath(path);

    for (final item in items) {
      final internalPath = _convertPath(path, item.mountPath);

      try {
        await for (final status in item.fileSystem.list(
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
        logger.warning('Failed to list $internalPath: $e');
        continue;
      }
    }
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    logger.info(
      'Moving from $source to $destination (overwrite: ${options.overwrite}, '
      'recursive: ${options.recursive})',
    );

    final sourceItem = await _getFirstReadableItemAsync(source);
    final destItem = _getFirstWritableItem(destination);

    if (sourceItem == null) {
      logger.warning('Move failed: source not found: $source');
      throw FileSystemException.notFound(source);
    }
    if (destItem == null) {
      logger.warning(
        'Move failed: no writable filesystem for destination: $destination',
      );
      throw FileSystemException.readOnly(destination);
    }
    if (sourceItem.readOnly) {
      logger.warning('Move failed: source filesystem is read-only: $source');
      throw FileSystemException.readOnly(source);
    }

    final sourceInternalPath = _convertPath(source, sourceItem.mountPath);
    final destInternalPath = _convertPath(destination, destItem.mountPath);

    // 如果源和目标在同一个文件系统中，直接移动
    if (sourceItem == destItem) {
      logger.fine(
        'Direct move within same filesystem: ${sourceItem.mountPath}',
      );
      await sourceItem.fileSystem.move(
        sourceInternalPath,
        destInternalPath,
        options: options,
      );
    } else {
      logger.fine(
        'Cross-filesystem move: '
        '${sourceItem.mountPath} -> ${destItem.mountPath}',
      );

      // 否则通过拷贝+删除实现跨文件系统移动
      await copy(
        source,
        destination,
        options: CopyOptions(
          overwrite: options.overwrite,
          recursive: options.recursive,
        ),
      );

      await delete(
        source,
        options: DeleteOptions(recursive: options.recursive),
      );
    }

    logger.info('Move completed: $source -> $destination');
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    logger.fine(
      'Opening read stream for: '
      '$path (start: ${options.start}, end: ${options.end})',
    );

    final item = await _getFirstReadableItemAsync(path);
    if (item == null) {
      logger.warning('Open read failed: file not found: $path');
      yield* Stream.error(FileSystemException.notFound(path));
      return;
    }

    final internalPath = _convertPath(path, item.mountPath);
    logger.fine('Reading from filesystem ${item.mountPath}: $internalPath');

    yield* item.fileSystem.openRead(internalPath, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    logger.fine('Opening write stream for: $path (mode: ${options.mode})');

    final item = _getFirstWritableItem(path);
    if (item == null) {
      logger.warning('Open write failed: no writable filesystem for: $path');
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(path, item.mountPath);
    logger.fine('Writing to filesystem ${item.mountPath}: $internalPath');

    return item.fileSystem.openWrite(internalPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async {
    logger.fine(
      'Reading bytes for: $path (start: ${options.start}, end: ${options.end})',
    );

    final item = await _getFirstReadableItemAsync(path);
    if (item == null) {
      logger.warning('Read bytes failed: file not found: $path');
      throw FileSystemException.notFound(path);
    }

    final internalPath = _convertPath(path, item.mountPath);
    logger.fine(
      'Reading bytes from filesystem ${item.mountPath}: $internalPath',
    );

    final data = await item.fileSystem.readAsBytes(
      internalPath,
      options: options,
    );
    logger.fine('Read ${data.length} bytes from: $path');
    return data;
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final items = _getItemsForPath(path);

    for (final item in items) {
      final internalPath = _convertPath(path, item.mountPath);
      final status = await item.fileSystem.stat(internalPath, options: options);
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
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    logger.fine(
      'Writing ${data.length} bytes to: $path (mode: ${options.mode})',
    );

    final item = _getFirstWritableItem(path);
    if (item == null) {
      logger.warning('Write bytes failed: no writable filesystem for: $path');
      throw FileSystemException.readOnly(path);
    }

    final internalPath = _convertPath(path, item.mountPath);
    logger.fine('Writing bytes to filesystem ${item.mountPath}: $internalPath');

    await item.fileSystem.writeBytes(internalPath, data, options: options);
    logger.fine('Successfully wrote ${data.length} bytes to: $path');
  }
}
