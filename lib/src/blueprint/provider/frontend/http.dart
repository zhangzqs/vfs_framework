import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/abstract/index.dart';

import '../../../frontend/http.dart';
import '../../engine/core.dart';

part 'http.g.dart';

@JsonSerializable()
class _Config {
  _Config({
    required this.backend,
    this.address = 'localhost',
    this.port = 8456,
  });
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  final String backend;
  final String address;
  final int port;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  HttpServer build(BuildContext ctx) {
    if (backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for HTTP file system',
      );
    }
    return HttpServer(
      ctx.mustGetComponentByName<IFileSystem>(backend),
      address: address,
      port: port,
    );
  }
}

class HttpServerProvider extends ComponentProvider<HttpServer> {
  @override
  String get type => 'frontend.http';

  @override
  Future<HttpServer> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    final runner = cfg.build(ctx);
    unawaited(runner.start());
    return runner;
  }

  @override
  Future<void> close(BuildContext ctx, HttpServer component) async {
    await component.stop();
  }
}
