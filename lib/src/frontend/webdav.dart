import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:vfs_framework/src/abstract/index.dart';
import 'package:vfs_framework/src/helper/context_shelf_middleware.dart';
import 'package:vfs_framework/vfs_framework.dart';

/// WebDAV服务器实现
class WebDAVServer {
  WebDAVServer(
    this.fs, {
    this.address = 'localhost',
    this.port = 8080,
    Logger? logger,
  }) : logger = logger ?? Logger.defaultLogger;

  final IFileSystem fs;
  io.HttpServer? _server;
  final String address;
  final int port;
  final Logger logger;

  /// 启动WebDAV服务器
  Future<io.HttpServer> start() async {
    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware)
        .addMiddleware(contextMiddleware(logger))
        .addHandler(handleRequest);

    _server = await serve(handler, address, port);
    logger.info(
      'WebDAV服务器启动在 http://${_server!.address.host}:${_server!.port}',
    );
    return _server!;
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  /// CORS中间件
  Middleware get _corsMiddleware => (Handler innerHandler) {
    final corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': _routerHandler.keys.join(', '),
      'Access-Control-Allow-Headers':
          'Content-Type, Authorization, Depth, Destination, Overwrite',
      'Access-Control-Max-Age': '86400',
    };
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: {...response.headers, ...corsHeaders});
    };
  };

  late final _routerHandler =
      <
        String,
        Future<Response> Function(Context context, Path path, Request request)
      >{
        'GET': _handleGet,
        'PUT': _handlePut,
        'DELETE': _handleDelete,
        'MKCOL': _handleMkcol,
        'PROPFIND': _handlePropfind,
        'PROPPATCH': _handleProppatch,
        'COPY': _handleCopy,
        'MOVE': _handleMove,
        'HEAD': _handleHead,
        'OPTIONS': _handleOptions,
      };

  /// 主要的请求处理器
  Future<Response> handleRequest(Request request) async {
    final method = request.method.toUpperCase();
    final path = _getPathFromRequest(request);
    final context = mustGetContextFromRequest(request);
    final logger = context.logger;

    logger.debug('处理 $method 请求: $path');

    try {
      if (!_routerHandler.containsKey(method)) {
        logger.warning('不支持的方法: $method');
        return Response(
          405,
          headers: {'Allow': _routerHandler.keys.join(', ')},
        );
      }
      return await _routerHandler[method]!(context, path, request);
    } catch (e, stackTrace) {
      logger.error('处理请求时发生错误', error: e, stackTrace: stackTrace);
      return Response.internalServerError(body: '服务器内部错误: $e');
    }
  }

  /// 从请求中提取路径
  Path _getPathFromRequest(Request request) {
    var segments = request.url.pathSegments;

    // 移除空的segments（由尾随斜杠造成）
    segments = segments.where((s) => s.isNotEmpty).toList();

    if (segments.isEmpty) {
      return Path.rootPath;
    }

    logger.trace('解析路径: ${request.url.path} -> segments: $segments');
    return Path(segments);
  }

  /// 处理GET请求 - 读取文件或列出目录
  Future<Response> _handleGet(
    Context context,
    Path path,
    Request request,
  ) async {
    final status = await fs.stat(context, path);
    if (status == null) {
      return Response.notFound('文件或目录不存在');
    }

    if (status.isDirectory) {
      // 目录：返回简单的HTML列表
      return await _handleDirectoryListing(context, path);
    } else {
      // 文件：返回文件内容
      return await _handleFileDownload(context, path, status, request);
    }
  }

  /// 处理PUT请求 - 上传文件
  Future<Response> _handlePut(
    Context context,
    Path path,
    Request request,
  ) async {
    try {
      final sink = await fs.openWrite(
        context,
        path,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      await for (final chunk in request.read()) {
        sink.add(chunk);
      }

      await sink.close();

      logger.info('文件上传成功: $path');
      return Response(201); // Created
    } on FileSystemException catch (e) {
      logger.warning('上传文件失败: $path, 错误: $e');
      return Response(409, body: '无法创建文件: ${e.message}');
    }
  }

  /// 处理DELETE请求 - 删除文件或目录
  Future<Response> _handleDelete(
    Context context,
    Path path,
    Request request,
  ) async {
    try {
      final status = await fs.stat(context, path);
      if (status == null) {
        return Response.notFound('文件或目录不存在');
      }

      await fs.delete(
        context,
        path,
        options: const DeleteOptions(recursive: true),
      );
      logger.info('删除成功: $path');
      return Response(204); // No Content
    } on FileSystemException catch (e) {
      logger.warning('删除失败: $path, 错误: $e');
      return Response(409, body: '无法删除: ${e.message}');
    }
  }

  /// 处理MKCOL请求 - 创建目录
  Future<Response> _handleMkcol(
    Context context,
    Path path,
    Request request,
  ) async {
    try {
      await fs.createDirectory(
        context,
        path,
        options: const CreateDirectoryOptions(createParents: true),
      );
      logger.info('目录创建成功: $path');
      return Response(201); // Created
    } on FileSystemException catch (e) {
      if (e.code == FileSystemErrorCode.alreadyExists) {
        return Response(405, body: '目录已存在'); // Method not allowed
      }
      logger.warning('创建目录失败: $path, 错误: $e');
      return Response(409, body: '无法创建目录: ${e.message}');
    }
  }

  /// 处理PROPFIND请求 - 获取属性
  Future<Response> _handlePropfind(
    Context context,
    Path path,
    Request request,
  ) async {
    final depthHeader = request.headers['depth'] ?? '1';
    final depth = int.tryParse(depthHeader) ?? 1;

    logger.info('PROPFIND请求: path=$path, depth=$depth');

    final status = await fs.stat(context, path);
    if (status == null) {
      logger.warning('PROPFIND: 路径不存在: $path');
      return Response.notFound('文件或目录不存在');
    }

    logger.info(
      'PROPFIND: 路径状态: path=$path, isDirectory=${status.isDirectory}, '
      'size=${status.size}',
    );

    final responses = <String>[];

    // 添加当前路径的属性
    responses.add(_buildPropfindResponse(context, path, status));

    // 如果是目录且深度大于0，添加子项
    if (status.isDirectory && depth > 0) {
      logger.info('PROPFIND: 列出目录内容: $path');
      var childCount = 0;
      await for (final child in fs.list(context, path)) {
        childCount++;
        logger.debug(
          'PROPFIND: 添加子项: ${child.path} (${child.isDirectory ? "目录" : "文件"})',
        );
        responses.add(_buildPropfindResponse(context, child.path, child));
      }
      logger.info('PROPFIND: 目录 $path 包含 $childCount 个子项');
    }

    final xml = _buildMultistatusXml(responses);
    logger.debug('PROPFIND响应XML:\n$xml');

    return Response(
      207, // Multi-Status
      body: xml,
      headers: {'Content-Type': 'application/xml; charset=utf-8'},
    );
  }

  /// 处理PROPPATCH请求 - 设置属性（暂不实现）
  Future<Response> _handleProppatch(
    Context context,
    Path path,
    Request request,
  ) async {
    // WebDAV属性修改，暂时返回不支持
    return Response(403, body: '属性修改暂不支持');
  }

  /// 处理COPY请求 - 复制文件或目录
  Future<Response> _handleCopy(
    Context context,
    Path path,
    Request request,
  ) async {
    final destinationHeader = request.headers['destination'];
    if (destinationHeader == null) {
      return Response(400, body: '缺少Destination头');
    }

    final destinationUri = Uri.parse(destinationHeader);
    final destinationPath = Path(destinationUri.pathSegments);

    final overwriteHeader = request.headers['overwrite']?.toLowerCase();
    final overwrite = overwriteHeader == 't' || overwriteHeader == 'true';

    try {
      await fs.copy(
        context,
        path,
        destinationPath,
        options: CopyOptions(overwrite: overwrite, recursive: true),
      );
      logger.info('复制成功: $path -> $destinationPath');
      return Response(201); // Created
    } on FileSystemException catch (e) {
      logger.warning('复制失败: $path -> $destinationPath, 错误: $e');
      return Response(409, body: '无法复制: ${e.message}');
    }
  }

  /// 处理MOVE请求 - 移动文件或目录
  Future<Response> _handleMove(
    Context context,
    Path path,
    Request request,
  ) async {
    final destinationHeader = request.headers['destination'];
    if (destinationHeader == null) {
      return Response(400, body: '缺少Destination头');
    }

    final destinationUri = Uri.parse(destinationHeader);
    final destinationPath = Path(destinationUri.pathSegments);

    final overwriteHeader = request.headers['overwrite']?.toLowerCase();
    final overwrite = overwriteHeader == 't' || overwriteHeader == 'true';

    try {
      await fs.move(
        context,
        path,
        destinationPath,
        options: MoveOptions(overwrite: overwrite, recursive: true),
      );
      logger.info('移动成功: $path -> $destinationPath');
      return Response(201); // Created
    } on FileSystemException catch (e) {
      logger.warning('移动失败: $path -> $destinationPath, 错误: $e');
      return Response(409, body: '无法移动: ${e.message}');
    }
  }

  /// 处理HEAD请求 - 仅返回头信息
  Future<Response> _handleHead(
    Context context,
    Path path,
    Request request,
  ) async {
    final status = await fs.stat(context, path);
    if (status == null) {
      return Response.notFound('');
    }

    final headers = <String, String>{
      'Content-Type': status.isDirectory
          ? 'httpd/unix-directory'
          : (status.mimeType ?? 'application/octet-stream'),
    };

    if (!status.isDirectory && status.size != null) {
      headers['Content-Length'] = status.size.toString();
      headers['Accept-Ranges'] = 'bytes'; // 告诉客户端我们支持Range请求
    }

    return Response.ok('', headers: headers);
  }

  /// 处理OPTIONS请求 - 返回支持的方法
  Future<Response> _handleOptions(
    Context context,
    Path path,
    Request request,
  ) async {
    return Response.ok(
      '',
      headers: {'Allow': _routerHandler.keys.join(', '), 'DAV': '1, 2'},
    );
  }

  /// 处理目录列表（HTML格式）
  Future<Response> _handleDirectoryListing(Context context, Path path) async {
    final items = <String>[];

    await for (final item in fs.list(context, path)) {
      final name = item.path.filename ?? '';
      final isDir = item.isDirectory;
      final size = item.size ?? 0;

      items.add('''
        <tr>
          <td><a href="${_encodePathForUrl(item.path)}">${_escapeHtml(name)}${isDir ? '/' : ''}</a></td>
          <td>${isDir ? '-' : _formatFileSize(size)}</td>
          <td>${isDir ? 'Directory' : 'File'}</td>
        </tr>
      ''');
    }

    final html =
        '''
<!DOCTYPE html>
<html>
<head>
    <title>目录列表 - ${_escapeHtml(path.toString())}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        a { text-decoration: none; color: #0066cc; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>目录列表 - ${_escapeHtml(path.toString())}</h1>
    <table>
        <tr>
            <th>名称</th>
            <th>大小</th>
            <th>类型</th>
        </tr>
        ${items.join('\n')}
    </table>
</body>
</html>
    ''';

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// 处理文件下载
  Future<Response> _handleFileDownload(
    Context context,
    Path path,
    FileStatus status,
    Request request,
  ) async {
    final logger = context.logger;
    final mimeType = status.mimeType ?? 'application/octet-stream';
    final fileSize = status.size;

    // 检查是否有Range请求头
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null && fileSize != null) {
      return await _handleRangeRequest(
        context,
        path,
        fileSize,
        rangeHeader,
        mimeType,
      );
    }
    // 标准的完整文件下载
    final headers = <String, String>{
      'Content-Type': mimeType,
      'Accept-Ranges': 'bytes', // 告诉客户端我们支持Range请求
      if (fileSize != null) 'Content-Length': fileSize.toString(),
    };
    logger.debug('下载文件: $path, MIME类型: $mimeType, 大小: $fileSize');

    return Response.ok(
      fs.openRead(context, path),
      headers: headers,
      context: {'shelf.io.buffer_output': false}, // 关闭缓冲
    );
  }

  /// 处理HTTP Range请求，返回206 Partial Content
  Future<Response> _handleRangeRequest(
    Context context,
    Path path,
    int fileSize,
    String rangeHeader,
    String mimeType,
  ) async {
    logger.debug('处理Range请求: $path, Range: $rangeHeader, FileSize: $fileSize');

    // 解析Range头：bytes=start-end
    final rangeMatch = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
    if (rangeMatch == null) {
      logger.warning('无效的Range头格式: $rangeHeader');
      return Response(
        416, // Range Not Satisfiable
        headers: {'Content-Range': 'bytes */$fileSize'},
        body: 'Invalid Range header',
      );
    }

    final startStr = rangeMatch.group(1);
    final endStr = rangeMatch.group(2);

    int start;
    int end;

    try {
      // 解析开始位置
      if (startStr == null || startStr.isEmpty) {
        // 后缀范围：bytes=-500 (最后500字节)
        if (endStr == null || endStr.isEmpty) {
          return Response(
            416, // Range Not Satisfiable
            headers: {'Content-Range': 'bytes */$fileSize'},
            body: 'Invalid Range header',
          );
        }
        final suffixLength = int.parse(endStr);
        start = math.max(0, fileSize - suffixLength);
        end = fileSize - 1;
      } else {
        start = int.parse(startStr);
        if (endStr == null || endStr.isEmpty) {
          // 前缀范围：bytes=500- (从500到结束)
          end = fileSize - 1;
        } else {
          // 标准范围：bytes=500-999
          end = int.parse(endStr);
        }
      }

      // 验证范围
      if (start < 0 || end >= fileSize || start > end) {
        logger.warning('范围超出文件大小: start=$start, end=$end, fileSize=$fileSize');
        return Response(
          416, // Range Not Satisfiable
          headers: {'Content-Range': 'bytes */$fileSize'},
          body: 'Range not satisfiable',
        );
      }

      final contentLength = end - start + 1;
      logger.info('发送部分内容: $path, 范围: $start-$end ($contentLength bytes)');

      // 构建响应头
      final headers = <String, String>{
        'Content-Type': mimeType,
        'Content-Length': contentLength.toString(),
        'Content-Range': 'bytes $start-$end/$fileSize',
        'Accept-Ranges': 'bytes',
      };

      // 使用ReadOptions指定范围
      final stream = fs.openRead(
        context,
        path,
        options: ReadOptions(start: start, end: end + 1),
      );

      return Response(
        206, // Partial Content
        body: stream,
        headers: headers,
        // context: {'shelf.io.buffer_output': false}, // 关闭缓冲
      );
    } catch (e) {
      logger.warning('解析Range头时出错: $rangeHeader, 错误: $e');
      return Response(
        416, // Range Not Satisfiable
        headers: {'Content-Range': 'bytes */$fileSize'},
        body: 'Invalid Range header: $e',
      );
    }
  }

  /// 构建PROPFIND响应
  String _buildPropfindResponse(Context context, Path path, FileStatus status) {
    final href = _buildHrefForPath(path, status.isDirectory);
    final isCollection = status.isDirectory;
    final size = status.size ?? 0;
    final mimeType = status.mimeType ?? 'application/octet-stream';

    return '''
    <d:response>
        <d:href>$href</d:href>
        <d:propstat>
            <d:prop>
                <d:displayname>${_escapeXml(path.filename ?? '')}</d:displayname>
                <d:resourcetype>${isCollection ? '<d:collection/>' : ''}</d:resourcetype>
                <d:getcontentlength>$size</d:getcontentlength>
                <d:getcontenttype>$mimeType</d:getcontenttype>
                <d:creationdate>${DateTime.now().toUtc().toIso8601String()}</d:creationdate>
                <d:getlastmodified>${_formatHttpDate(DateTime.now())}</d:getlastmodified>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
    </d:response>''';
  }

  /// 为路径构建正确的href，目录需要尾随斜杠
  String _buildHrefForPath(Path path, bool isDirectory) {
    if (path.isRoot) {
      return '/';
    }

    final encodedSegments = path.segments.map(Uri.encodeComponent).join('/');
    final href = '/$encodedSegments';

    // WebDAV规范要求目录路径以斜杠结尾
    return isDirectory ? '$href/' : href;
  }

  /// 构建多状态XML响应
  String _buildMultistatusXml(List<String> responses) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
${responses.join('\n')}
</d:multistatus>''';
  }

  /// URL编码路径
  String _encodePathForUrl(Path path) {
    if (path.isRoot) {
      return '/';
    }

    final encodedSegments = path.segments.map(Uri.encodeComponent).join('/');

    // 对于目录，添加尾随斜杠
    // 注意：我们需要从上下文判断是否为目录，这里先不添加
    return '/$encodedSegments';
  }

  /// HTML转义
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// XML转义
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// 格式化HTTP日期
  String _formatHttpDate(DateTime dateTime) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final utc = dateTime.toUtc();
    final weekday = weekdays[utc.weekday - 1];
    final month = months[utc.month - 1];

    return '$weekday, ${utc.day.toString().padLeft(2, '0')} $month ${utc.year} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')} GMT';
  }
}
