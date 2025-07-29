import 'package:dio/dio.dart';

import 'propfind_xml.dart';

class WebDAVDio {
  WebDAVDio(this.dio) {
    dio.options.validateStatus = (status) => true;
  }
  final Dio dio;

  // 用于删除操作
  Future<Response<void>> delete(
    String path, {
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.delete(path, options: options, cancelToken: cancelToken);
  }

  // 用于创建文件夹
  Future<Response<void>> mkcol(
    String path, {
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.request(
      path,
      options: (options ?? Options()).copyWith(method: 'MKCOL'),
      cancelToken: cancelToken,
    );
  }

  // 可以用于ping之类的操作
  Future<Response<void>> options(
    String path, {
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.request(
      path,
      options: (options ?? Options()).copyWith(method: 'OPTIONS'),
      cancelToken: cancelToken,
    );
  }

  // 流式读取文件
  Future<Response<ResponseBody>> getStream(
    String path, {
    int? start, // 闭区间
    int? end, // 开区间
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final headers = <String, Object>{};
    if (start != null && end != null) {
      headers['Range'] = 'bytes=$start-$end';
    } else if (start != null) {
      headers['Range'] = 'bytes=$start-';
    } else if (end != null) {
      headers['Range'] = 'bytes=0-$end';
    }
    final resp = await dio.get<ResponseBody>(
      path,
      options: (options ?? Options()).copyWith(
        responseType: ResponseType.stream,
        headers: headers,
      ),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
    return resp;
  }

  Future<Response<void>> head(
    String path, {
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.head(path, options: options, cancelToken: cancelToken);
  }

  // 流式写入文件
  Future<Response<void>> putStream(
    String path,
    Stream<List<int>> data, {
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return dio.put<void>(
      path,
      data: data,
      options: (options ?? Options()).copyWith(
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  // copy or move
  Future<Response<void>> copyOrMove(
    String fromPath,
    String toPath, {
    bool isMove = false,
    bool overwrite = false,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.request<void>(
      fromPath,
      options: (options ?? Options()).copyWith(
        method: isMove ? 'MOVE' : 'COPY',
        headers: {'Destination': toPath, 'Overwrite': overwrite ? 'T' : 'F'},
      ),
      cancelToken: cancelToken,
    );
  }

  // propfind
  Future<Response<WebDAVPropfindResponse>> propfind(
    String path, {
    int depth = 1,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final resp = await dio.request<String>(
      path,
      options: (options ?? Options()).copyWith(
        method: 'PROPFIND',
        headers: {
          'Depth': depth.toString(),
          'Accept': 'application/xml, text/xml',
          'Accept-Charset': 'utf-8',
        },
        contentType: 'application/xml; charset=utf-8',
      ),
      cancelToken: cancelToken,
      data: propfindRequestXML,
    );
    final ret = Response<WebDAVPropfindResponse>(
      statusCode: resp.statusCode,
      statusMessage: resp.statusMessage,
      headers: resp.headers,
      requestOptions: resp.requestOptions,
      isRedirect: resp.isRedirect,
      redirects: resp.redirects,
      extra: resp.extra,
    );
    if (resp.statusCode == 207) {
      assert(resp.data != null, 'Expected data to be non-null');
      ret.data = WebDAVPropfindResponse.fromXml(resp.data!);
    }
    return ret;
  }
}
