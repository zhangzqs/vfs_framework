import 'dart:async';
import 'dart:typed_data';

import '../abstract/index.dart';

/// 用于把另一个文件系统里的某个子文件夹作为一个新文件系统
class AliasFileSystem extends IFileSystem {
  AliasFileSystem({
    required this.fileSystem,
    Path? subDirectory,
    String loggerName = 'AliasFileSystem',
  }) : subDirectory = subDirectory ?? Path.rootPath;

  final IFileSystem fileSystem;
  final Path subDirectory;

  /// 将alias路径转换为底层文件系统的实际路径
  Path _convertToRealPath(Context context, Path aliasPath) {
    final logger = context.logger;
    if (subDirectory.isRoot) {
      logger.trace(
        '转换别名路径（根目录情况）',
        metadata: {
          'alias_path': aliasPath.toString(),
          'real_path': aliasPath.toString(),
          'subdirectory': 'root',
          'operation': 'convert_to_real_path_root',
        },
      );
      return aliasPath;
    }
    // 将alias路径与子目录路径合并
    final realPath = subDirectory.joinAll(aliasPath.segments);
    logger.trace(
      '转换别名路径',
      metadata: {
        'alias_path': aliasPath.toString(),
        'real_path': realPath.toString(),
        'subdirectory': subDirectory.toString(),
        'operation': 'convert_to_real_path',
      },
    );
    return realPath;
  }

  /// 将底层文件系统的路径转换为alias路径
  Path _convertFromRealPath(Context context, Path realPath) {
    final logger = context.logger;
    if (subDirectory.isRoot) {
      logger.trace(
        '转换真实路径（根目录情况）',
        metadata: {
          'real_path': realPath.toString(),
          'alias_path': realPath.toString(),
          'subdirectory': 'root',
          'operation': 'convert_from_real_path_root',
        },
      );
      return realPath;
    }

    // 检查路径是否在子目录下
    if (realPath.segments.length < subDirectory.segments.length) {
      logger.warning(
        '真实路径长度不足',
        metadata: {
          'real_path': realPath.toString(),
          'real_path_segments': realPath.segments.length,
          'subdirectory_depth': subDirectory.segments.length,
          'operation': 'path_too_short_error',
        },
      );
      throw ArgumentError('Real path is not under subdirectory');
    }

    // 验证路径前缀匹配
    for (int i = 0; i < subDirectory.segments.length; i++) {
      if (realPath.segments[i] != subDirectory.segments[i]) {
        logger.warning(
          '路径前缀不匹配',
          metadata: {
            'real_path': realPath.toString(),
            'subdirectory': subDirectory.toString(),
            'mismatch_index': i,
            'expected_segment': subDirectory.segments[i],
            'actual_segment': realPath.segments[i],
            'operation': 'path_prefix_mismatch_error',
          },
        );
        throw ArgumentError('Real path is not under subdirectory');
      }
    }

    // 移除子目录前缀
    final aliasPath = Path.rootPath.joinAll(
      realPath.segments.sublist(subDirectory.segments.length),
    );
    logger.trace(
      '转换真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'alias_path': aliasPath.toString(),
        'removed_subdirectory': subDirectory.toString(),
        'operation': 'convert_from_real_path',
      },
    );
    return aliasPath;
  }

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
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
    final realSource = _convertToRealPath(context, source);
    final realDestination = _convertToRealPath(context, destination);
    logger.debug(
      '真实路径映射',
      metadata: {
        'real_source': realSource.toString(),
        'real_destination': realDestination.toString(),
        'operation': 'copy_real_paths',
      },
    );
    return fileSystem.copy(
      context,
      realSource,
      realDestination,
      options: options,
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '创建目录',
      metadata: {
        'path': path.toString(),
        'create_parents': options.createParents,
        'operation': 'create_directory',
      },
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'create_directory_real_path',
      },
    );
    return fileSystem.createDirectory(context, realPath, options: options);
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '删除文件',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'delete_file',
      },
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'delete_real_path',
      },
    );
    return fileSystem.delete(context, realPath, options: options);
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) {
    final logger = context.logger;
    logger.trace(
      '检查文件存在性',
      metadata: {'path': path.toString(), 'operation': 'check_exists'},
    );
    final realPath = _convertToRealPath(context, path);
    return fileSystem.exists(context, realPath, options: options);
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final logger = context.logger;
    logger.debug(
      '列举目录',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'list_directory',
      },
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'list_real_path',
      },
    );

    var itemCount = 0;
    await for (final status in fileSystem.list(
      context,
      realPath,
      options: options,
    )) {
      itemCount++;
      // 将真实路径转换为alias路径
      final aliasPath = _convertFromRealPath(context, status.path);

      yield FileStatus(
        path: aliasPath,
        isDirectory: status.isDirectory,
        size: status.size,
        mimeType: status.mimeType,
      );
    }
    logger.debug(
      '目录列举完成',
      metadata: {
        'path': path.toString(),
        'item_count': itemCount,
        'operation': 'list_directory_completed',
      },
    );
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '移动文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': options.overwrite,
        'recursive': options.recursive,
        'operation': 'move_file',
      },
    );
    final realSource = _convertToRealPath(context, source);
    final realDestination = _convertToRealPath(context, destination);
    logger.debug(
      '真实路径映射',
      metadata: {
        'real_source': realSource.toString(),
        'real_destination': realDestination.toString(),
        'operation': 'move_real_paths',
      },
    );
    return fileSystem.move(
      context,
      realSource,
      realDestination,
      options: options,
    );
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
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
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'open_read_real_path',
      },
    );
    return fileSystem.openRead(context, realPath, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '打开写入流',
      metadata: {
        'path': path.toString(),
        'mode': options.mode.toString(),
        'operation': 'open_write_stream',
      },
    );
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'open_write_real_path',
      },
    );
    return fileSystem.openWrite(context, realPath, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
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
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'read_bytes_real_path',
      },
    );
    return fileSystem.readAsBytes(context, realPath, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final logger = context.logger;
    logger.trace(
      '获取文件状态',
      metadata: {'path': path.toString(), 'operation': 'get_file_status'},
    );
    final realPath = _convertToRealPath(context, path);
    final realStatus = await fileSystem.stat(
      context,
      realPath,
      options: options,
    );

    if (realStatus == null) {
      logger.trace(
        '文件状态未找到',
        metadata: {
          'path': path.toString(),
          'operation': 'file_status_not_found',
        },
      );
      return null;
    }

    logger.trace(
      '文件状态已找到',
      metadata: {
        'path': path.toString(),
        'is_directory': realStatus.isDirectory,
        'size': realStatus.size,
        'mime_type': realStatus.mimeType,
        'operation': 'file_status_found',
      },
    );
    // 将真实路径转换为alias路径
    return FileStatus(
      path: path,
      isDirectory: realStatus.isDirectory,
      size: realStatus.size,
      mimeType: realStatus.mimeType,
    );
  }

  @override
  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) {
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
    final realPath = _convertToRealPath(context, path);
    logger.debug(
      '真实路径',
      metadata: {
        'real_path': realPath.toString(),
        'operation': 'write_bytes_real_path',
      },
    );
    return fileSystem.writeBytes(context, realPath, data, options: options);
  }
}
