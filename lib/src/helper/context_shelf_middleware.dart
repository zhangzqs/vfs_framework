import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import '../abstract/index.dart';

const _middlewareKey = 'vfs.context';

FileSystemContext mustGetContextFromRequest(Request request) {
  final context = request.context[_middlewareKey];
  if (context == null || context is! FileSystemContext) {
    throw StateError('FileSystemContext not found in request');
  }
  return context;
}

Middleware contextMiddleware(Logger logger) {
  return (Handler handler) {
    return (Request request) async {
      final requestID = const Uuid().v8();
      final context = FileSystemContext(logger: logger, operationID: requestID);

      // 将上下文添加到请求中
      final newRequest = request.change(
        context: {...request.context, _middlewareKey: context},
      );

      try {
        final response = await handler(newRequest);

        // 监听响应流完成或错误
        if (response.contentLength == null || response.contentLength! > 0) {
          final streamController = StreamController<List<int>>();

          response.read().listen(
            streamController.add,
            onError: (Object error) {
              logger.error('Response stream error: $error');
              context.cancel('Response stream error: $error');
              streamController.addError(error);
            },
            onDone: () async {
              logger.trace('Response completed');
              context.cancel('Response completed');
              await streamController.close();
            },
          );

          return response.change(
            body: streamController.stream,
            headers: {...response.headers, 'X-Request-ID': requestID},
          );
        }

        // 对于非流式响应，直接取消上下文
        context.cancel('Non-stream response completed');
        return response;
      } catch (e, s) {
        logger.error('Request failed', error: e, stackTrace: s);
        context.cancel('Request failed: ${e.toString()}');
        rethrow;
      }
    };
  };
}
