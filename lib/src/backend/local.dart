import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import '../abstract/index.dart';
import '../helper/filesystem_helper.dart';
import '../helper/mime_type_helper.dart';

class LocalFileSystem extends IFileSystem with FileSystemHelper {
  LocalFileSystem({Directory? baseDir, String loggerName = 'LocalFileSystem'})
    : baseDir = baseDir ?? Directory.current;

  /// 本地文件系统的基础目录
  final Directory baseDir;

  // 将抽象Path转换为本地文件系统路径
  String _toLocalPath(Context context, Path path) {
    final logger = context.logger;
    final localPath = p.join(baseDir.path, p.joinAll(path.segments));
    logger.trace(
      '转换抽象路径为本地路径',
      metadata: {
        'abstract_path': path.toString(),
        'local_path': localPath,
        'base_dir': baseDir.path,
        'operation': 'convert_to_local_path',
      },
    );
    return localPath;
  }

  // 将本地路径转换为抽象Path
  Path _toPath(Context context, String localPath) {
    final logger = context.logger;
    logger.trace(
      '转换本地路径为抽象路径',
      metadata: {
        'local_path': localPath,
        'operation': 'convert_to_abstract_path',
      },
    );
    // 计算相对于baseDir的相对路径
    String relative = p.relative(localPath, from: baseDir.path);

    // 处理特殊情况：根目录
    if (relative == '.') {
      logger.trace(
        '本地路径为根目录，返回空路径',
        metadata: {
          'local_path': localPath,
          'result': 'root_directory',
          'operation': 'convert_root_directory',
        },
      );
      return Path([]);
    }

    // 使用path包分割路径
    final abstractPath = Path(p.split(relative));
    logger.trace(
      '转换完成',
      metadata: {
        'local_path': localPath,
        'abstract_path': abstractPath.toString(),
        'relative_path': relative,
        'operation': 'convert_to_abstract_path_completed',
      },
    );
    return abstractPath;
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
    try {
      final localPath = _toLocalPath(context, path);
      logger.trace(
        '检查本地路径实体类型',
        metadata: {'local_path': localPath, 'operation': 'check_entity_type'},
      );
      final entity = FileSystemEntity.isDirectorySync(localPath)
          ? Directory(localPath)
          : File(localPath);

      if (!await entity.exists()) {
        logger.debug(
          '实体不存在',
          metadata: {
            'path': path.toString(),
            'local_path': localPath,
            'operation': 'entity_not_exists',
          },
        );
        return null;
      }

      final stat = await entity.stat();
      final fileStatus = FileStatus(
        path: path,
        size: stat.type == FileSystemEntityType.file ? stat.size : null,
        isDirectory: stat.type == FileSystemEntityType.directory,
        mimeType: stat.type == FileSystemEntityType.file
            ? detectMimeType(path.filename ?? '')
            : null,
      );

      logger.debug(
        '文件状态获取成功',
        metadata: {
          'path': path.toString(),
          'is_directory': fileStatus.isDirectory,
          'size': fileStatus.size,
          'mime_type': fileStatus.mimeType,
          'operation': 'file_status_retrieved',
        },
      );
      return fileStatus;
    } on FileSystemException {
      logger.warning(
        '获取文件状态时发生文件系统异常',
        metadata: {
          'path': path.toString(),
          'operation': 'filesystem_exception',
        },
      );
      rethrow;
    } on IOException catch (e) {
      logger.warning(
        '获取文件状态时发生IO异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'io_exception',
        },
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to get file status: ${e.toString()}',
        path: path,
      );
    }
  }

  Stream<FileStatus> nonRecursiveList(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final logger = context.logger;
    logger.debug(
      '开始非递归目录列举',
      metadata: {
        'path': path.toString(),
        'operation': 'start_non_recursive_list',
      },
    );
    final localPath = _toLocalPath(context, path);
    int itemCount = 0;

    await for (final entity in Directory(localPath).list()) {
      try {
        final stat = await entity.stat();
        final fileStatus = FileStatus(
          path: _toPath(context, entity.path),
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          isDirectory: stat.type == FileSystemEntityType.directory,
          mimeType: stat.type == FileSystemEntityType.file
              ? detectMimeType(p.basename(entity.path))
              : null,
        );
        itemCount++;
        logger.trace(
          '列举项目',
          metadata: {
            'item_number': itemCount,
            'path': fileStatus.path.toString(),
            'is_directory': fileStatus.isDirectory,
            'size': fileStatus.size,
            'operation': 'list_item',
          },
        );
        yield fileStatus;
      } on IOException catch (e) {
        logger.warning(
          '列举时发生IO异常',
          metadata: {
            'entity_path': entity.path,
            'error': e.toString(),
            'operation': 'list_io_exception',
          },
        );
        continue; // 跳过IO错误的文件
      }
    }

    logger.debug(
      '非递归目录列举完成',
      metadata: {
        'path': path.toString(),
        'item_count': itemCount,
        'operation': 'non_recursive_list_completed',
      },
    );
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '开始目录列举',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'start_directory_list',
      },
    );
    // 遍历目录
    return listImplByNonRecursive(
      context,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  Future<void> nonRecursiveCopyFile(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) {
    final logger = context.logger;
    logger.debug(
      '复制单个文件',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'operation': 'copy_single_file',
      },
    );
    return copyFileByReadAndWrite(
      context,
      source,
      destination,
      openWrite: openWrite,
      openRead: openRead,
    );
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
      '开始复制操作',
      metadata: {
        'source': source.toString(),
        'destination': destination.toString(),
        'overwrite': options.overwrite,
        'recursive': options.recursive,
        'operation': 'start_copy_operation',
      },
    );
    try {
      await copyImplByNonRecursive(
        context,
        source: source,
        destination: destination,
        options: options,
        nonRecursiveCopyFile: nonRecursiveCopyFile,
        nonRecursiveList: nonRecursiveList,
        nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
      );
      logger.info(
        '复制操作成功完成',
        metadata: {
          'source': source.toString(),
          'destination': destination.toString(),
          'operation': 'copy_operation_completed',
        },
      );
    } catch (e) {
      logger.warning(
        '复制操作失败',
        metadata: {
          'source': source.toString(),
          'destination': destination.toString(),
          'error': e.toString(),
          'operation': 'copy_operation_failed',
        },
      );
      rethrow;
    }
  }

  Future<void> nonRecursiveCreateDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '创建单个目录',
      metadata: {
        'path': path.toString(),
        'operation': 'create_single_directory',
      },
    );
    try {
      final localPath = _toLocalPath(context, path);
      final directory = Directory(localPath);

      // 检查父目录是否存在
      final parent = directory.parent;
      if (!await parent.exists()) {
        logger.warning(
          '父目录不存在',
          metadata: {
            'path': path.toString(),
            'parent_path': parent.path,
            'operation': 'parent_directory_not_exists',
          },
        );
        throw FileSystemException.notFound(_toPath(context, parent.path));
      }

      // 创建目录
      await directory.create();
      logger.debug(
        '目录创建成功',
        metadata: {
          'path': path.toString(),
          'local_path': localPath,
          'operation': 'directory_created',
        },
      );
    } on IOException catch (e) {
      logger.warning(
        '创建目录时发生IO异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'create_directory_io_exception',
        },
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to create directory: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
    final logger = context.logger;
    logger.info(
      '开始创建目录操作',
      metadata: {
        'path': path.toString(),
        'create_parents': options.createParents,
        'operation': 'start_create_directory_operation',
      },
    );
    return createDirectoryImplByNonRecursive(
      context,
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
      path: path,
      options: options,
    );
  }

  Future<void> nonRecursiveDelete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    final logger = context.logger;
    logger.debug(
      '删除单个实体',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'delete_single_entity',
      },
    );
    try {
      final localPath = _toLocalPath(context, path);
      final entity = FileSystemEntity.typeSync(localPath);

      switch (entity) {
        case FileSystemEntityType.file:
          logger.trace(
            '删除文件',
            metadata: {'path': path.toString(), 'operation': 'delete_file'},
          );
          await File(localPath).delete();
          break;
        case FileSystemEntityType.directory:
          logger.trace(
            '删除目录',
            metadata: {
              'path': path.toString(),
              'recursive': options.recursive,
              'operation': 'delete_directory',
            },
          );
          await Directory(localPath).delete(recursive: options.recursive);
          break;
        case FileSystemEntityType.link:
          logger.trace(
            '删除链接',
            metadata: {'path': path.toString(), 'operation': 'delete_link'},
          );
          await Link(localPath).delete();
          break;
        default:
          logger.warning(
            '不支持的实体类型',
            metadata: {
              'path': path.toString(),
              'entity_type': entity.toString(),
              'operation': 'unsupported_entity_type',
            },
          );
          throw FileSystemException.unsupportedEntity(path);
      }
      logger.debug(
        '实体删除成功',
        metadata: {'path': path.toString(), 'operation': 'entity_deleted'},
      );
    } on FileSystemException catch (e) {
      logger.warning(
        '删除时发生文件系统异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'delete_filesystem_exception',
        },
      );
      rethrow;
    } on IOException catch (e) {
      logger.warning(
        '删除时发生IO异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'delete_io_exception',
        },
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to delete: ${e.toString()}',
        path: path,
      );
    }
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    final logger = context.logger;
    logger.info(
      '开始删除操作',
      metadata: {
        'path': path.toString(),
        'recursive': options.recursive,
        'operation': 'start_delete_operation',
      },
    );
    return deleteImplByNonRecursive(
      context,
      nonRecursiveDelete: nonRecursiveDelete,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
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
    await preOpenWriteCheck(context, path, options: options);
    try {
      final sink = File(_toLocalPath(context, path)).openWrite(
        mode: {
          WriteMode.write: FileMode.write,
          WriteMode.overwrite: FileMode.writeOnly,
          WriteMode.append: FileMode.append,
        }[options.mode]!,
      );
      logger.debug(
        '写入流打开成功',
        metadata: {'path': path.toString(), 'operation': 'write_stream_opened'},
      );
      return sink;
    } on IOException catch (e) {
      logger.warning(
        '打开写入流时发生IO异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'open_write_stream_io_exception',
        },
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to open write stream: ${e.toString()}',
        path: path,
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
    await preOpenReadCheck(context, path, options: options);
    try {
      int bytesRead = 0;
      // 打开文件并读取内容
      await for (final chunk in File(
        _toLocalPath(context, path),
      ).openRead(options.start, options.end)) {
        bytesRead += chunk.length;
        logger.trace(
          '读取数据块',
          metadata: {
            'chunk_size': chunk.length,
            'path': path.toString(),
            'operation': 'read_chunk',
          },
        );
        yield chunk; // 逐块返回文件内容
      }
      logger.debug(
        '读取流完成',
        metadata: {
          'path': path.toString(),
          'total_bytes': bytesRead,
          'operation': 'read_stream_completed',
        },
      );
    } on IOException catch (e) {
      logger.warning(
        '读取文件时发生IO异常',
        metadata: {
          'path': path.toString(),
          'error': e.toString(),
          'operation': 'read_file_io_exception',
        },
      );
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Failed to read file: ${e.toString()}',
        path: path,
      );
    }
  }
}
