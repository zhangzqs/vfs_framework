import 'dart:convert';
import 'dart:io' as io;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:vfs_framework/src/abstract/index.dart';
import 'package:vfs_framework/src/helper/context_shelf_middleware.dart';

import '../logger/index.dart';

class HttpServer {
  HttpServer(
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

  /// 启动HTTP服务器
  Future<io.HttpServer> start() async {
    final handler = const Pipeline()
        .addMiddleware(contextMiddleware(logger))
        .addHandler(handleRequest);

    _server = await serve(handler, address, port);
    return _server!;
  }

  /// 路由处理器
  Future<Response> handleRequest(Request request) async {
    final context = mustGetContextFromRequest(request);
    final uri = request.requestedUri;
    final method = request.method;
    final pathSegments = uri.pathSegments;

    try {
      if (method == 'GET') {
        if (pathSegments.isEmpty ||
            (pathSegments.length == 1 && pathSegments[0].isEmpty)) {
          // 根目录列表
          return await _handleList(context, Path.rootPath, request);
        } else {
          final path = Path.rootPath.joinAll(pathSegments);

          // 检查是否存在查询参数来强制列表操作
          if (request.url.queryParameters.containsKey('list')) {
            return await _handleList(context, path, request);
          }

          // 首先检查路径是否存在
          final status = await fs.stat(context, path);
          if (status == null) {
            return Response.notFound('路径不存在: ${path.toString()}');
          }

          if (status.isDirectory) {
            return await _handleList(context, path, request);
          } else {
            return await _handleGet(context, path, request);
          }
        }
      }

      return Response.notFound('不支持的操作');
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 处理文件列表请求
  Future<Response> _handleList(
    Context context,
    Path path,
    Request request,
  ) async {
    try {
      final recursive = request.url.queryParameters['recursive'] == 'true';
      final options = ListOptions(recursive: recursive);

      final files = <Map<String, dynamic>>[];
      await for (final fileStatus in fs.list(context, path, options: options)) {
        files.add({
          'name': fileStatus.path.filename ?? '/',
          'path': fileStatus.path.toString(),
          'isDirectory': fileStatus.isDirectory,
          'size': fileStatus.size,
          'mimeType': fileStatus.mimeType,
        });
      }

      // 按目录优先，然后按名称排序
      files.sort((a, b) {
        if (a['isDirectory'] != b['isDirectory']) {
          return a['isDirectory'] == true ? -1 : 1;
        }
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      final acceptHeader = request.headers['accept'] ?? '';

      if (acceptHeader.contains('application/json')) {
        // 返回JSON格式
        return Response.ok(
          json.encode({'path': path.toString(), 'files': files}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      } else {
        // 返回HTML格式
        return Response.ok(
          _generateHtmlList(path, files),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': '列表文件失败: ${e.toString()}'}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 处理文件下载请求
  Future<Response> _handleGet(
    Context context,
    Path path,
    Request request,
  ) async {
    try {
      final fileStatus = await fs.stat(context, path);
      if (fileStatus == null) {
        return Response.notFound('文件不存在: ${path.toString()}');
      }

      if (fileStatus.isDirectory) {
        return Response.badRequest(
          body: json.encode({'error': '不能下载目录，请使用列表操作'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // 处理Range请求（部分内容下载）
      final rangeHeader = request.headers['range'];
      int? start;
      int? end;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final range = rangeHeader.substring(6);
        final parts = range.split('-');
        if (parts.length == 2) {
          start = parts[0].isNotEmpty ? int.tryParse(parts[0]) : null;
          // HTTP Range请求中的end是包含性的，但ReadOptions中的end是排他性的
          final rangeEnd = parts[1].isNotEmpty ? int.tryParse(parts[1]) : null;
          end = rangeEnd != null ? rangeEnd + 1 : null;
        }
      }

      final readOptions = ReadOptions(start: start, end: end);
      final stream = fs.openRead(context, path, options: readOptions);

      final headers = <String, String>{
        'content-type': fileStatus.mimeType ?? 'application/octet-stream',
        'content-disposition': _buildContentDisposition(
          fileStatus.path.filename,
        ),
      };

      if (fileStatus.size != null) {
        if (start != null || end != null) {
          final actualStart = start ?? 0;
          // 对于content-range头，我们需要显示原始的包含性结束位置
          final actualEnd = (end != null ? end - 1 : (fileStatus.size! - 1));
          final contentLength = actualEnd - actualStart + 1;

          headers['content-range'] =
              'bytes $actualStart-$actualEnd/${fileStatus.size}';
          headers['content-length'] = contentLength.toString();
          headers['accept-ranges'] = 'bytes';

          return Response(206, headers: headers, body: stream);
        } else {
          headers['content-length'] = fileStatus.size.toString();
          headers['accept-ranges'] = 'bytes';
        }
      }

      return Response.ok(stream, headers: headers);
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': '下载文件失败: ${e.toString()}'}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 生成HTML文件列表页面
  String _generateHtmlList(Path path, List<Map<String, dynamic>> files) {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html>');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="utf-8">');
    buffer.writeln('<title>文件列表 - ${path.toString()}</title>');
    buffer.writeln('<style>');
    buffer.writeln('body { font-family: Arial, sans-serif; margin: 20px; }');
    buffer.writeln('table { border-collapse: collapse; width: 100%; }');
    buffer.writeln(
      'th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }',
    );
    buffer.writeln('th { background-color: #f2f2f2; }');
    buffer.writeln('a { text-decoration: none; color: #0066cc; }');
    buffer.writeln('a:hover { text-decoration: underline; }');
    buffer.writeln('.directory { font-weight: bold; }');
    buffer.writeln('.file-size { text-align: right; }');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<h1>文件列表: ${path.toString()}</h1>');

    // 添加返回上级目录的链接
    if (!path.isRoot) {
      final parentPath = path.parent?.toString() ?? '/';
      buffer.writeln('<p><a href="$parentPath">← 返回上级目录</a></p>');
    }

    buffer.writeln('<table>');
    buffer.writeln('<tr><th>名称</th><th>类型</th><th>大小</th><th>MIME类型</th></tr>');

    for (final file in files) {
      final name = file['name'] as String;
      final filePath = file['path'] as String;
      final isDirectory = file['isDirectory'] as bool;
      final size = file['size'] as int?;
      final mimeType = file['mimeType'] as String?;

      buffer.writeln('<tr>');

      // 名称列
      if (isDirectory) {
        buffer.writeln(
          '<td><a href="$filePath" class="directory">📁 $name</a></td>',
        );
      } else {
        buffer.writeln('<td><a href="$filePath">📄 $name</a></td>');
      }

      // 类型列
      buffer.writeln('<td>${isDirectory ? '目录' : '文件'}</td>');

      // 大小列
      if (size != null && !isDirectory) {
        buffer.writeln('<td class="file-size">${_formatFileSize(size)}</td>');
      } else {
        buffer.writeln('<td class="file-size">-</td>');
      }

      // MIME类型列
      buffer.writeln('<td>${mimeType ?? '-'}</td>');

      buffer.writeln('</tr>');
    }

    buffer.writeln('</table>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 构建符合HTTP标准的Content-Disposition头部
  String _buildContentDisposition(String? filename) {
    if (filename == null || filename.isEmpty) {
      return 'inline';
    }

    // 检查文件名是否只包含ASCII字符
    bool isAsciiOnly = filename.codeUnits.every((unit) => unit < 128);

    if (isAsciiOnly) {
      // 如果是纯ASCII字符，使用简单格式
      return 'inline; filename="$filename"';
    } else {
      // 如果包含非ASCII字符，使用RFC 5987标准的编码格式
      final encodedFilename = Uri.encodeComponent(filename);
      return 'inline; filename*=UTF-8\'\'$encodedFilename';
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close();
  }
}
