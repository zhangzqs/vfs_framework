import 'dart:async';

import 'package:dio/dio.dart';
import 'package:vfs_framework/src/backend/webdav/propfind_xml.dart';
import 'package:vfs_framework/src/backend/webdav/webdav_dio.dart';
import 'package:vfs_framework/src/helper/filesystem_helper.dart';
import 'package:vfs_framework/vfs_framework.dart';

class WebDAVFileSystem extends IFileSystem with FileSystemHelper {
  WebDAVFileSystem(Dio dio) : webdavDio = WebDAVDio(dio);

  final WebDAVDio webdavDio;
  Future<void> ping(Context context) async {
    final resp = await webdavDio.options(
      '/',
      cancelToken: _getCancelToken(context),
    );
    if (resp.statusCode == 200) {
      return;
    }
    throw FileSystemException.ioError(
      Path.rootPath,
      resp.statusMessage ?? 'Ping failed',
    );
  }

  CancelToken _getCancelToken(Context context) {
    final token = CancelToken();
    Future.microtask(() async {
      final e = await context.whenCancel;
      if (!token.isCancelled) {
        token.cancel('Operation cancelled by context: ${e.message}');
      }
    });
    return token;
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async* {
    await preOpenReadCheck(context, path, options: options);
    final resp = await webdavDio.getStream(
      path.toString(),
      start: options.start,
      end: options.end,
      cancelToken: _getCancelToken(context),
    );

    if (resp.statusCode == 200 || resp.statusCode == 206) {
      yield* resp.data!.stream;
      return; // 成功返回，避免抛出异常
    }
    if (resp.statusCode == 403) {
      throw FileSystemException.permissionDenied(path);
    }
    if (resp.statusCode == 404) {
      throw FileSystemException.notFound(path);
    }
    throw FileSystemException.ioError(
      path,
      resp.statusMessage ?? 'Failed to open read stream',
    );
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    if (options.mode == WriteMode.append) {
      throw FileSystemException.notImplemented(
        path,
        'Append mode not implemented for WebDAV',
      );
    }
    await preOpenWriteCheck(context, path, options: options);

    // 创建一个StreamController用于真正的流式传输
    final streamController = StreamController<List<int>>();
    final completer = Completer<void>();

    // 立即开始PUT请求，使用流式数据
    _startPutRequest(context, path, streamController.stream, completer);

    // 返回自定义的StreamSink
    return _WebDAVWriteSink(
      streamController.sink,
      completer.future,
      onClose: streamController.close,
    );
  }

  /// 开始流式PUT请求
  void _startPutRequest(
    Context context,
    Path path,
    Stream<List<int>> dataStream,
    Completer<void> completer,
  ) async {
    final logger = context.logger;
    try {
      logger.debug(
        '开始流式PUT请求',
        metadata: {'path': path.toString(), 'operation': 'start_put_request'},
      );

      // 使用流式PUT请求
      final resp = await webdavDio.putStream(
        path.toString(),
        dataStream,
        cancelToken: _getCancelToken(context),
      );

      logger.debug(
        'PUT请求完成',
        metadata: {
          'path': path.toString(),
          'status_code': resp.statusCode,
          'operation': 'put_request_completed',
        },
      );

      // 检查响应状态
      if (resp.statusCode == 201 ||
          resp.statusCode == 204 ||
          resp.statusCode == 200) {
        logger.debug(
          '文件写入成功',
          metadata: {
            'path': path.toString(),
            'status_code': resp.statusCode,
            'operation': 'file_write_success',
          },
        );
        completer.complete();
      } else if (resp.statusCode == 403) {
        logger.warning(
          '文件写入权限被拒绝',
          metadata: {
            'path': path.toString(),
            'status_code': resp.statusCode,
            'operation': 'file_write_permission_denied',
          },
        );
        completer.completeError(FileSystemException.permissionDenied(path));
      } else if (resp.statusCode == 409) {
        logger.warning(
          '父目录不存在',
          metadata: {
            'path': path.toString(),
            'status_code': resp.statusCode,
            'operation': 'parent_directory_not_found',
          },
        );
        completer.completeError(FileSystemException.notFound(path));
      } else {
        final errorMessage = resp.statusMessage ?? 'Failed to write file';
        logger.warning(
          '文件写入失败',
          metadata: {
            'path': path.toString(),
            'status_code': resp.statusCode,
            'error_message': errorMessage,
            'operation': 'file_write_failed',
          },
        );
        completer.completeError(
          FileSystemException.ioError(path, errorMessage),
        );
      }
    } catch (e, stackTrace) {
      logger.error(
        'PUT请求过程中发生错误',
        error: e,
        stackTrace: stackTrace,
        metadata: {'path': path.toString(), 'operation': 'put_request_error'},
      );
      completer.completeError(e);
    }
  }

  Future<void> nonRecursiveCopyFile(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    final resp = await webdavDio.copyOrMove(
      source.toString(),
      destination.toString(),
      overwrite: options.overwrite,
      cancelToken: _getCancelToken(context),
    );
    if (resp.statusCode == 201 || resp.statusCode == 204) {
      return; // 成功拷贝
    }
    if (resp.statusCode == 403) {
      throw FileSystemException.permissionDenied(source);
    }
    if (resp.statusCode == 404) {
      throw FileSystemException.notFound(source);
    }
    throw FileSystemException.ioError(
      source,
      resp.statusMessage ?? 'Failed to copy file',
    );
  }

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    await copyImplByNonRecursive(
      context,
      source: source,
      destination: destination,
      options: options,
      nonRecursiveCopyFile: nonRecursiveCopyFile,
      nonRecursiveList: nonRecursiveList,
      nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
    );
  }

  Future<void> nonRecursiveCreateDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    final logger = context.logger;
    if (path.isRoot) {
      return; // 根目录不需要创建
    }
    // 检查父目录是否存在
    final parentPath = path.parent;
    if (parentPath != null) {
      final parentStat = await stat(context, parentPath);
      if (parentStat == null) {
        throw FileSystemException.notFound(parentPath);
      } else {
        if (!parentStat.isDirectory) {
          throw FileSystemException.notADirectory(parentPath);
        } else {
          // 父目录存在且是目录
          logger.debug(
            '父目录存在',
            metadata: {
              'parent_path': parentPath.toString(),
              'path': path.toString(),
              'operation': 'parent_directory_exists',
            },
          );
        }
      }
    }
    final resp = await webdavDio.mkcol(
      path.toString(),
      cancelToken: _getCancelToken(context),
    );
    if (resp.statusCode == 201 || resp.statusCode == 405) {
      return; // 成功创建或已存在
    }
    if (resp.statusCode == 403) {
      throw FileSystemException.permissionDenied(path);
    }
    if (resp.statusCode == 404) {
      throw FileSystemException.notFound(path);
    }
    throw FileSystemException.ioError(
      path,
      resp.statusMessage ?? 'Failed to create directory',
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) {
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
    final statRes = await stat(context, path);
    if (statRes == null) {
      throw FileSystemException.notFound(path);
    }
    final resp = await webdavDio.delete(
      path.toString(),
      cancelToken: _getCancelToken(context),
    );
    if (resp.statusCode == 204 || resp.statusCode == 200) {
      return; // 成功删除
    }
    if (resp.statusCode == 403) {
      throw FileSystemException.permissionDenied(path);
    }
    if (resp.statusCode == 404) {
      throw FileSystemException.notFound(path);
    }
    throw FileSystemException.ioError(
      path,
      resp.statusMessage ?? 'Failed to delete',
    );
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) {
    return deleteImplByNonRecursive(
      context,
      nonRecursiveDelete: nonRecursiveDelete,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  Stream<FileStatus> nonRecursiveList(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    final resp = await webdavDio.propfind(
      path.toString(),
      depth: 1,
      cancelToken: _getCancelToken(context),
    );
    if (resp.statusCode == 404) {
      throw FileSystemException.notFound(path);
    }
    if (resp.statusCode == 403) {
      throw FileSystemException.permissionDenied(path);
    }
    if (resp.statusCode == 207) {
      assert(resp.data != null, 'Expected data to be non-null');
      for (final response in resp.data!.multistatus.responses) {
        // 跳过自身路径
        if (Path.fromString(response.href) == path) {
          continue;
        }
        yield _buildFileStatusFromWebDAVResponse(response);
      }
      return;
    }
    throw FileSystemException.ioError(
      path,
      resp.statusMessage ?? 'Failed to list directory',
    );
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    // 遍历目录
    return listImplByNonRecursive(
      context,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  FileStatus _buildFileStatusFromWebDAVResponse(WebDAVResponse resp) {
    return FileStatus(
      isDirectory: resp.isDirectory,
      path: Path.fromString(resp.href),
      size: resp.contentLength,
      mimeType: resp.contentType,
    );
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    final ret = await webdavDio.propfind(
      path.toString(),
      depth: 0,
      cancelToken: _getCancelToken(context),
    );
    if (ret.statusCode == 404) {
      return null;
    }
    if (ret.statusCode == 207) {
      assert(ret.data != null, 'Expected data to be non-null');
      return _buildFileStatusFromWebDAVResponse(
        ret.data!.multistatus.responses.first,
      );
    }
    if (ret.statusCode == 403) {
      throw FileSystemException.permissionDenied(path);
    }
    throw FileSystemException.ioError(
      path,
      ret.statusMessage ?? 'Failed to get file status',
    );
  }
}

/// 自定义的StreamSink实现，封装WebDAV写入逻辑
class _WebDAVWriteSink implements StreamSink<List<int>> {
  _WebDAVWriteSink(this._sink, this._doneFuture, {this.onClose});

  final StreamSink<List<int>> _sink;
  final Future<void> _doneFuture;
  final void Function()? onClose;

  @override
  void add(List<int> data) {
    _sink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _sink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _sink.addStream(stream);
  }

  @override
  Future<void> close() {
    onClose?.call();
    return _doneFuture;
  }

  @override
  Future<void> get done => _doneFuture;
}
