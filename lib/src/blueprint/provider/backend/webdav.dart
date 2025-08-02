import 'package:dio/dio.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/helper/go_duration_helper.dart';

import '../../../abstract/index.dart';
import '../../../backend/index.dart';
import '../../engine/index.dart';

part 'webdav.g.dart';

@JsonSerializable()
class _HttpOptions {
  const _HttpOptions({
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
  });

  factory _HttpOptions.fromJson(Map<String, dynamic> json) =>
      _$HttpOptionsFromJson(json);

  @GoDurationStringConverter()
  final Duration connectTimeout;

  @GoDurationStringConverter()
  final Duration receiveTimeout;

  @GoDurationStringConverter()
  final Duration sendTimeout;
  Map<String, dynamic> toJson() => _$HttpOptionsToJson(this);
}

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.httpOptions = const _HttpOptions(),
  });

  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String baseUrl;
  final String username;
  final String password;
  final _HttpOptions httpOptions;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  WebDAVFileSystem build(BuildContext ctx) {
    final baseOptions = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: httpOptions.connectTimeout,
      receiveTimeout: httpOptions.receiveTimeout,
      sendTimeout: httpOptions.sendTimeout,
    );

    final dio = Dio(baseOptions);

    dio.interceptors.add(
      WebDAVBasicAuthInterceptor(username: username, password: password),
    );
    return WebDAVFileSystem(dio);
  }
}

class WebDAVFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.webdav';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }
}
