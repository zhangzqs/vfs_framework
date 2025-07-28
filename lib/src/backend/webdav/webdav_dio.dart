import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'auth.dart';
import 'client.dart';
import 'utils.dart';

/// Wrapped HTTP client for WebDAV operations
class WdDio with DioMixin implements Dio {
  /// Interceptors list
  final List<Interceptor>? interceptorList;

  /// Debug mode flag
  final bool debug;

  WdDio({
    BaseOptions? options,
    this.interceptorList,
    this.debug = false,
  }) {
    this.options = options ?? BaseOptions();
    // 禁止重定向
    this.options.followRedirects = false;

    // 状态码错误视为成功
    this.options.validateStatus = (status) => true;

    // 拦截器
    if (interceptorList != null) {
      for (final item in interceptorList!) {
        interceptors.add(item);
      }
    }

    // debug
    if (debug) {
      interceptors.add(LogInterceptor(responseBody: true));
    }
  }

  /// Generic request method with proper error handling and authentication
  Future<Response<T>> req<T>(
    Client self,
    String method,
    String path, {
    dynamic data,
    void Function(Options)? optionsHandler,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    // options
    final options = Options(method: method);
    options.headers ??= <String, dynamic>{};

    // 二次处理options
    optionsHandler?.call(options);

    // authorization
    final authStr = self.auth.authorize(method, path);
    if (authStr != null) {
      options.headers!['authorization'] = authStr;
    }

    final fullPath = path.startsWith(RegExp(r'(http|https)://')) 
        ? path 
        : join(self.uri, path);

    var resp = await requestUri<T>(
      Uri.parse(fullPath),
      options: options,
      data: data,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );

    if (resp.statusCode == 401) {
      final w3AHeader = resp.headers.value('www-authenticate');
      final lowerW3AHeader = w3AHeader?.toLowerCase();

      // before is noAuth
      if (self.auth.type == AuthType.noAuth) {
        // Digest
        if (lowerW3AHeader?.contains('digest') == true) {
          self.auth = DigestAuth(
            user: self.auth.user,
            pwd: self.auth.pwd,
            dParts: DigestParts(w3AHeader),
          );
        }
        // Basic
        else if (lowerW3AHeader?.contains('basic') == true) {
          self.auth = BasicAuth(user: self.auth.user, pwd: self.auth.pwd);
        }
        // error
        else {
          throw newResponseError(resp);
        }
      }
      // before is digest and Nonce Lifetime is out
      else if (self.auth.type == AuthType.digestAuth &&
          lowerW3AHeader?.contains('stale=true') == true) {
        self.auth = DigestAuth(
          user: self.auth.user,
          pwd: self.auth.pwd,
          dParts: DigestParts(w3AHeader),
        );
      } else {
        throw newResponseError(resp);
      }

      // retry
      return req<T>(
        self,
        method,
        path,
        data: data,
        optionsHandler: optionsHandler,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
    } else if (resp.statusCode == 302) {
      // 文件位置被重定向到新路径
      final locationList = resp.headers.map['location'];
      if (locationList != null && locationList.isNotEmpty) {
        final redirectPath = locationList.first;
        // retry
        return req<T>(
          self,
          method,
          redirectPath,
          data: data,
          optionsHandler: optionsHandler,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
          cancelToken: cancelToken,
        );
      }
    }

    return resp;
  }

  /// WebDAV OPTIONS method
  Future<Response<dynamic>> wdOptions(
    Client self,
    String path, {
    CancelToken? cancelToken,
  }) {
    return req<dynamic>(
      self,
      'OPTIONS',
      path,
      optionsHandler: (options) => options.headers?['depth'] = '0',
      cancelToken: cancelToken,
    );
  }

  // // quota
  // Future<Response> wdQuota(Client self, String dataStr,
  //     {CancelToken cancelToken}) {
  //   return this.req(self, 'PROPFIND', '/', data: utf8.encode(dataStr),
  //       optionsHandler: (options) {
  //     options.headers['depth'] = '0';
  //     options.headers['accept'] = 'text/plain';
  //   }, cancelToken: cancelToken);
  // }

  /// WebDAV PROPFIND method
  Future<Response<String>> wdPropfind(
    Client self,
    String path,
    bool depth,
    String dataStr, {
    CancelToken? cancelToken,
  }) async {
    final resp = await req<String>(
      self,
      'PROPFIND',
      path,
      data: dataStr,
      optionsHandler: (options) {
        options.headers?['depth'] = depth ? '1' : '0';
        options.headers?['content-type'] = 'application/xml;charset=UTF-8';
        options.headers?['accept'] = 'application/xml,text/xml';
        options.headers?['accept-charset'] = 'utf-8';
        options.headers?['accept-encoding'] = '';
      },
      cancelToken: cancelToken,
    );

    if (resp.statusCode != 207) {
      throw newResponseError(resp);
    }

    return resp;
  }

  /// WebDAV MKCOL method
  Future<Response<dynamic>> wdMkcol(
    Client self,
    String path, {
    CancelToken? cancelToken,
  }) {
    return req<dynamic>(self, 'MKCOL', path, cancelToken: cancelToken);
  }

  /// WebDAV DELETE method
  Future<Response<dynamic>> wdDelete(
    Client self,
    String path, {
    CancelToken? cancelToken,
  }) {
    return req<dynamic>(self, 'DELETE', path, cancelToken: cancelToken);
  }

  /// WebDAV COPY OR MOVE method
  Future<void> wdCopyMove(
    Client self,
    String oldPath,
    String newPath,
    bool isCopy,
    bool overwrite, {
    CancelToken? cancelToken,
  }) async {
    final method = isCopy ? 'COPY' : 'MOVE';
    final resp = await req<dynamic>(
      self,
      method,
      oldPath,
      optionsHandler: (options) {
        options.headers?['destination'] = Uri.encodeFull(
          join(self.uri, newPath),
        );
        options.headers?['overwrite'] = overwrite ? 'T' : 'F';
      },
      cancelToken: cancelToken,
    );

    final status = resp.statusCode;
    // TODO 207
    switch (status) {
      case 201:
      case 204:
      case 207:
        return;
      case 409:
        await _createParent(self, newPath, cancelToken: cancelToken);
        return wdCopyMove(
          self,
          oldPath,
          newPath,
          isCopy,
          overwrite,
          cancelToken: cancelToken,
        );
      default:
        throw newResponseError(resp);
    }
  }

  /// Create parent folder if it doesn't exist
  Future<void>? _createParent(
    Client self,
    String path, {
    CancelToken? cancelToken,
  }) {
    final parentPath = path.substring(0, path.lastIndexOf('/') + 1);

    if (parentPath == '' || parentPath == '/') {
      return null;
    }
    return self.mkdirAll(parentPath, cancelToken);
  }

  /// Read a file as bytes
  Future<List<int>> wdReadWithBytes(
    Client self,
    String path, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (pResp.statusCode != 200) {
      throw newResponseError(pResp);
    }

    final resp = await req<List<int>>(
      self,
      'GET',
      path,
      optionsHandler: (options) => options.responseType = ResponseType.bytes,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
    
    if (resp.statusCode != 200) {
      if (resp.statusCode != null && 
          resp.statusCode! >= 300 && 
          resp.statusCode! < 400) {
        final location = resp.headers['location']?.first;
        if (location != null) {
          final redirectResp = await req<List<int>>(
            self,
            'GET',
            location,
            optionsHandler: (options) =>
                options.responseType = ResponseType.bytes,
            onReceiveProgress: onProgress,
            cancelToken: cancelToken,
          );
          return redirectResp.data!;
        }
      }
      throw newResponseError(resp);
    }
    return resp.data!;
  }

  /// Read a file as stream and save to local path
  Future<void> wdReadWithStream(
    Client self,
    String path,
    String savePath, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (pResp.statusCode != 200) {
      throw newResponseError(pResp);
    }

    Response<ResponseBody> resp;

    // Request with stream response type
    try {
      resp = await req<ResponseBody>(
        self,
        'GET',
        path,
        optionsHandler: (options) => options.responseType = ResponseType.stream,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        if (e.response!.requestOptions.receiveDataWhenStatusError == true) {
          final res = await transformer.transformResponse(
            e.response!.requestOptions..responseType = ResponseType.json,
            e.response!.data as ResponseBody,
          );
          e.response!.data = res;
        } else {
          e.response!.data = null;
        }
      }
      rethrow;
    }
    
    if (resp.statusCode != 200) {
      throw newResponseError(resp);
    }

    resp.headers = Headers.fromMap(resp.data!.headers);

    // Create file and prepare for writing
    final file = File(savePath);
    file.createSync(recursive: true);

    var raf = file.openSync(mode: FileMode.write);

    // Create completer for async operation
    final completer = Completer<Response<ResponseBody>>();
    final future = completer.future;
    var received = 0;

    // Get content info
    final stream = resp.data!.stream;
    var compressed = false;
    var total = 0;
    final contentEncoding = resp.headers.value(Headers.contentEncodingHeader);
    if (contentEncoding != null) {
      compressed = ['gzip', 'deflate', 'compress'].contains(contentEncoding);
    }
    if (compressed) {
      total = -1;
    } else {
      total = int.parse(
        resp.headers.value(Headers.contentLengthHeader) ?? '-1',
      );
    }

    late StreamSubscription<Uint8List> subscription;
    Future<void>? asyncWrite;
    var closed = false;
    
    Future<void> closeAndDelete() async {
      if (!closed) {
        closed = true;
        await asyncWrite;
        await raf.close();
        await file.delete();
      }
    }

    subscription = stream.listen(
      (Uint8List data) {
        subscription.pause();
        // Write file asynchronously
        asyncWrite = raf
            .writeFrom(data)
            .then((updatedRaf) {
              // Notify progress
              received += data.length;
              onProgress?.call(received, total);

              raf = updatedRaf;
              if (cancelToken == null || !cancelToken.isCancelled) {
                subscription.resume();
              }
            })
            .catchError((Object err) async {
              try {
                await subscription.cancel();
              } finally {
                completer.completeError(
                  DioException(requestOptions: resp.requestOptions, error: err),
                );
              }
            });
      },
      onDone: () async {
        try {
          await asyncWrite;
          closed = true;
          await raf.close();
          completer.complete(resp);
        } catch (err) {
          completer.completeError(
            DioException(requestOptions: resp.requestOptions, error: err),
          );
        }
      },
      onError: (Object e) async {
        try {
          await closeAndDelete();
        } finally {
          completer.completeError(
            DioException(requestOptions: resp.requestOptions, error: e),
          );
        }
      },
      cancelOnError: true,
    );

    // Handle cancellation
    cancelToken?.whenCancel.then((_) async {
      await subscription.cancel();
      await closeAndDelete();
    });

    // Handle timeout
    if (resp.requestOptions.receiveTimeout != null &&
        resp.requestOptions.receiveTimeout!.compareTo(
              const Duration(milliseconds: 0),
            ) > 0) {
      try {
        await future.timeout(resp.requestOptions.receiveTimeout!);
      } on TimeoutException {
        await subscription.cancel();
        await closeAndDelete();
        throw DioException(
          requestOptions: resp.requestOptions,
          error:
              'Receiving data timeout[${resp.requestOptions.receiveTimeout}ms]',
          type: DioExceptionType.receiveTimeout,
        );
      } catch (err) {
        await subscription.cancel();
        await closeAndDelete();
        rethrow;
      }
    } else {
      await future;
    }
  }

  /// Write bytes to a file
  Future<void> wdWriteWithBytes(
    Client self,
    String path,
    Uint8List data, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (pResp.statusCode != 200) {
      throw newResponseError(pResp);
    }

    // mkdir
    await _createParent(self, path, cancelToken: cancelToken);

    final resp = await req<dynamic>(
      self,
      'PUT',
      path,
      data: Stream.fromIterable(data.map((e) => [e])),
      optionsHandler: (options) =>
          options.headers?['content-length'] = data.length,
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    
    final status = resp.statusCode;
    if (status == 200 || status == 201 || status == 204) {
      return;
    }
    throw newResponseError(resp);
  }

  /// Write stream to a file
  Future<void> wdWriteWithStream(
    Client self,
    String path,
    Stream<List<int>> data,
    int length, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // fix auth error
    final pResp = await wdOptions(self, path, cancelToken: cancelToken);
    if (pResp.statusCode != 200) {
      throw newResponseError(pResp);
    }

    // mkdir
    await _createParent(self, path, cancelToken: cancelToken);

    final resp = await req<dynamic>(
      self,
      'PUT',
      path,
      data: data,
      optionsHandler: (options) => options.headers?['content-length'] = length,
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
    
    final status = resp.statusCode;
    if (status == 200 || status == 201 || status == 204) {
      return;
    }
    throw newResponseError(resp);
  }
}
