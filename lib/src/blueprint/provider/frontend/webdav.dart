import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/abstract/filesystem.dart';
import 'package:vfs_framework/src/blueprint/engine/core.dart';
import 'package:vfs_framework/src/frontend/index.dart';

import '../../../logger/index.dart';

part 'webdav.g.dart';

@JsonSerializable()
class _Config {
  _Config({
    required this.backend,
    this.logger,
    this.requestLogger,
    this.address = 'localhost',
    this.port = 8080,
  });

  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String? logger;
  final String? requestLogger;
  final String backend;
  final String address;
  final int port;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  WebDAVServer build(BuildContext ctx) {
    if (backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for WebDAV file system',
      );
    }
    return WebDAVServer(
      ctx.mustGetComponentByName<IFileSystem>(backend),
      address: address,
      port: port,
      logger: logger == null
          ? null
          : ctx.mustGetComponentByName<Logger>(logger!),
      requestLogger: requestLogger == null
          ? null
          : ctx.mustGetComponentByName<Logger>(requestLogger!),
    );
  }
}

class WebDAVServerProvider extends ComponentProvider<WebDAVServer> {
  @override
  String get type => 'frontend.webdav';

  @override
  Future<WebDAVServer> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    final server = cfg.build(ctx);
    unawaited(server.start());
    return server;
  }

  @override
  Future<void> close(BuildContext ctx, WebDAVServer component) async {
    await component.stop();
  }
}
