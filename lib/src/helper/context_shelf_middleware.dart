import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:vfs_framework/src/helper/req_logger_shelf_middleware.dart';
import '../abstract/index.dart';

const _middlewareKey = 'vfs.context';

Context mustGetContextFromRequest(Request request) {
  final context = request.context[_middlewareKey];
  if (context == null || context is! Context) {
    throw StateError('FileSystemContext not found in request');
  }
  return context;
}

Request requestWithContext(Request request, Context context) {
  return request.change(context: {...request.context, _middlewareKey: context});
}

Middleware contextMiddleware(Logger logger) {
  return (Handler handler) {
    return (Request request) async {
      final requestID = mustGetRequestIDFromContext(request);
      final context = Context(
        logger: logger.withMetadata({'requestID': requestID}),
        operationID: requestID,
      );
      logger = context.logger;

      // 将上下文添加到请求中
      final newRequest = requestWithContext(request, context);

      try {
        logger.trace('请求到来: ${newRequest.method} ${newRequest.url}');
        final response = await handler(newRequest);
        logger.trace(
          '响应已发出: ${newRequest.method} ${newRequest.url} '
          '-> ${response.statusCode}',
        );

        // 监听响应流完成或错误
        if (response.contentLength == null || response.contentLength! > 0) {
          late final StreamController<List<int>> streamController;
          streamController = StreamController<List<int>>(
            sync: true,
            onListen: () {
              response.read().listen(
                (data) {
                  if (streamController.isClosed) return;
                  streamController.add(data);
                },
                onError: (Object error) {
                  logger.error('响应流错误: $error');
                  if (streamController.isClosed) return;
                  context.cancel('Response stream error: $error');
                  streamController.addError(error);
                },
                onDone: () async {
                  logger.trace('响应流结束');
                  if (streamController.isClosed) return;
                  context.cancel('Response completed');
                  await streamController.close();
                },
              );
            },
            onCancel: () async {
              if (streamController.isClosed) return;
              logger.debug('响应流已取消: ${newRequest.url}');
              context.cancel('Response stream cancelled');
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
