import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../logger/index.dart';

/// 请求日志中间件配置
class RequestLoggerConfig {
  const RequestLoggerConfig({
    this.requestBodyLimit = 10240, // 10KB
    this.responseBodyLimit = 10240, // 10KB
    this.addRequestIdHeader = true,
    this.requestIdHeaderName = 'X-Request-ID',
    this.logRequestBody = true,
    this.logResponseBody = true,
    this.logHeaders = true,
    this.logQueryParams = true,
  });

  /// 记录请求体的最大字节数
  final int requestBodyLimit;

  /// 记录响应体的最大字节数
  final int responseBodyLimit;

  /// 是否添加请求ID到响应头
  final bool addRequestIdHeader;

  /// 请求ID响应头名称
  final String requestIdHeaderName;

  /// 是否记录请求体
  final bool logRequestBody;

  /// 是否记录响应体
  final bool logResponseBody;

  /// 是否记录请求头
  final bool logHeaders;

  /// 是否记录查询参数
  final bool logQueryParams;
}

/// 请求体录制器
class _RequestBodyRecorder {
  _RequestBodyRecorder(this._stream, this.limit);

  final Stream<List<int>> _stream;
  final int limit;
  final List<int> _buffer = [];

  /// 获取录制的数据
  List<int> get recordedData => List.unmodifiable(_buffer);

  /// 获取限制长度的数据
  String get limitedBodyAsString {
    final data = _buffer.take(limit).toList();
    try {
      return utf8.decode(data);
    } catch (e) {
      // 如果不是有效的UTF-8，返回十六进制表示
      return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  /// 创建新的流，同时录制数据
  Stream<List<int>> createRecordingStream() async* {
    await for (final chunk in _stream) {
      // 录制数据
      if (_buffer.length < limit) {
        final remainingSpace = limit - _buffer.length;
        final chunkToRecord = chunk.take(remainingSpace).toList();
        _buffer.addAll(chunkToRecord);
      }

      yield chunk;
    }
  }
}

/// 响应体录制器
class _ResponseBodyRecorder {
  _ResponseBodyRecorder(this.limit);

  final int limit;
  final List<int> _buffer = [];

  /// 记录数据
  void record(List<int> data) {
    if (_buffer.length < limit) {
      final remainingSpace = limit - _buffer.length;
      final dataToRecord = data.take(remainingSpace).toList();
      _buffer.addAll(dataToRecord);
    }
  }

  /// 获取限制长度的数据
  String get limitedBodyAsString {
    try {
      return utf8.decode(_buffer);
    } catch (e) {
      // 如果不是有效的UTF-8，返回十六进制表示
      return _buffer.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }
}

/// 获取客户端IP地址
String _getClientIp(Request request) {
  // 检查常见的代理头
  final xForwardedFor = request.headers['x-forwarded-for'];
  if (xForwardedFor != null && xForwardedFor.isNotEmpty) {
    return xForwardedFor.split(',').first.trim();
  }

  final xRealIp = request.headers['x-real-ip'];
  if (xRealIp != null && xRealIp.isNotEmpty) {
    return xRealIp.trim();
  }

  // 从连接信息获取
  final connectionInfo =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return connectionInfo?.remoteAddress.address ?? 'unknown';
}

/// 格式化持续时间为人类可读的字符串
String _formatDuration(Duration duration) {
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds}ms';
  } else if (duration.inSeconds < 60) {
    final ms = duration.inMilliseconds % 1000;
    return '${duration.inSeconds}.${ms.toString().padLeft(3, '0')}s';
  } else {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m${seconds}s';
  }
}

/// 格式化文件大小
String _formatSize(int? bytes) {
  if (bytes == null) return 'unknown';
  if (bytes == 0) return '0B';

  const suffixes = ['B', 'KB', 'MB', 'GB'];
  final i = (log(bytes) / log(1024)).floor();
  final size = bytes / pow(1024, i);

  if (i == 0) {
    return '${bytes}B';
  } else {
    return '${size.toStringAsFixed(1)}${suffixes[i]}';
  }
}

const _middlewareReqIDKey = 'vfs.requestID';

String mustGetRequestIDFromContext(Request request) {
  final requestId = request.context[_middlewareReqIDKey];
  if (requestId is String) {
    return requestId;
  } else {
    throw StateError('Request ID not found in context');
  }
}

Request requestWithRequestID(Request request, String requestId) {
  return request.change(
    context: {...request.context, _middlewareReqIDKey: requestId},
  );
}

/// 创建请求日志中间件
Middleware requestLoggerMiddleware({
  Logger? logger,
  RequestLoggerConfig config = const RequestLoggerConfig(),
}) {
  final log = logger ?? Logger.defaultLogger;

  return (Handler innerHandler) {
    return (Request request) async {
      final requestId = const Uuid().v8();
      request = requestWithRequestID(request, requestId);

      final startTime = DateTime.now();
      final stopwatch = Stopwatch()..start();

      // 记录请求体
      _RequestBodyRecorder? requestRecorder;
      Request modifiedRequest = request;

      if (config.logRequestBody) {
        try {
          // 读取请求体数据进行记录
          final bodyStream = request.read();
          requestRecorder = _RequestBodyRecorder(
            bodyStream,
            config.requestBodyLimit,
          );

          // 重新创建带有录制功能的请求
          modifiedRequest = request.change(
            body: requestRecorder.createRecordingStream(),
          );
        } catch (e) {
          // 如果请求没有body或已经被读取，忽略错误
          modifiedRequest = request;
        }
      }

      // 记录响应体
      final responseRecorder = _ResponseBodyRecorder(config.responseBodyLimit);

      try {
        // 调用下一个处理器
        final response = await innerHandler(modifiedRequest);
        stopwatch.stop();

        // 修改响应以添加请求ID头和录制响应体
        Response finalResponse = response;

        if (config.addRequestIdHeader) {
          finalResponse = response.change(
            headers: {
              ...response.headers,
              config.requestIdHeaderName: requestId,
            },
          );
        }

        // 响应体记录比较复杂，需要拦截响应流
        // 由于Shelf的设计，我们简化处理，不记录响应体内容
        // 如果需要记录响应体，可以使用更复杂的流拦截机制

        // 记录日志
        await _logRequest(
          log: log,
          config: config,
          requestId: requestId,
          request: modifiedRequest,
          response: finalResponse,
          duration: stopwatch.elapsed,
          startTime: startTime,
          requestRecorder: requestRecorder,
          responseRecorder: responseRecorder,
        );

        return finalResponse;
      } catch (error, stackTrace) {
        stopwatch.stop();

        // 记录错误日志
        log.error(
          'Request failed',
          error: error,
          stackTrace: stackTrace,
          metadata: {
            'request_id': requestId,
            'method': modifiedRequest.method,
            'path': modifiedRequest.url.path,
            'duration': stopwatch.elapsed.inMilliseconds,
            'duration_human': _formatDuration(stopwatch.elapsed),
          },
        );

        rethrow;
      }
    };
  };
}

/// 记录请求日志
Future<void> _logRequest({
  required Logger log,
  required RequestLoggerConfig config,
  required String requestId,
  required Request request,
  required Response response,
  required Duration duration,
  required DateTime startTime,
  _RequestBodyRecorder? requestRecorder,
  required _ResponseBodyRecorder responseRecorder,
}) async {
  // 构建请求信息
  final requestInfo = <String, dynamic>{
    'method': request.method,
    'path': request.url.path,
    'host': request.headers['host'] ?? 'unknown',
    'client_ip': _getClientIp(request),
    'content_length': request.headers['content-length'],
    'content_type': request.headers['content-type'],
  };

  if (config.logQueryParams && request.url.query.isNotEmpty) {
    requestInfo['raw_query'] = request.url.query;
    requestInfo['query'] = request.url.queryParameters;
  }

  if (config.logHeaders) {
    requestInfo['headers'] = Map<String, String>.from(request.headers);
  }

  if (config.logRequestBody && requestRecorder != null) {
    requestInfo['body'] = requestRecorder.limitedBodyAsString;
  }

  // 构建响应信息
  final responseInfo = <String, dynamic>{
    'status': response.statusCode,
    'content_length': response.headers['content-length'],
    'content_type': response.headers['content-type'],
  };

  if (config.logHeaders) {
    responseInfo['headers'] = Map<String, String>.from(response.headers);
  }

  if (config.logResponseBody) {
    responseInfo['body'] = responseRecorder.limitedBodyAsString;
  }

  // 确定响应大小
  int? responseSize;
  final contentLength = response.headers['content-length'];
  if (contentLength != null) {
    responseSize = int.tryParse(contentLength);
  }

  // 记录日志
  log.info(
    'HTTP Request Log',
    metadata: {
      'x_request_id': requestId,
      'timestamp': startTime.toIso8601String(),
      'timestamp_human': startTime.toLocal().toString(),
      'request': requestInfo,
      'response': responseInfo,
      'duration_ms': duration.inMilliseconds,
      'duration_human': _formatDuration(duration),
      if (responseSize != null) 'response_size': responseSize,
      'response_size_human': _formatSize(responseSize),
    },
  );
}

/// 请求日志中间件的便捷创建函数
Middleware createRequestLogger({
  Logger? logger,
  int requestBodyLimit = 10240,
  int responseBodyLimit = 10240,
  bool addRequestIdHeader = true,
  String requestIdHeaderName = 'X-Request-ID',
  bool logRequestBody = true,
  bool logResponseBody = true,
  bool logHeaders = true,
  bool logQueryParams = true,
}) {
  return requestLoggerMiddleware(
    logger: logger,
    config: RequestLoggerConfig(
      requestBodyLimit: requestBodyLimit,
      responseBodyLimit: responseBodyLimit,
      addRequestIdHeader: addRequestIdHeader,
      requestIdHeaderName: requestIdHeaderName,
      logRequestBody: logRequestBody,
      logResponseBody: logResponseBody,
      logHeaders: logHeaders,
      logQueryParams: logQueryParams,
    ),
  );
}
