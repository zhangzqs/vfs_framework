import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/abstract/filesystem.dart';
import 'package:vfs_framework/src/blueprint/engine/core.dart';
import 'package:vfs_framework/src/frontend/index.dart';
import 'package:vfs_framework/src/helper/webdav_auth_middleware.dart';

import '../../../logger/index.dart';

part 'webdav.g.dart';

@JsonSerializable()
class _AuthConfig {
  _AuthConfig({this.type = AuthType.none, this.realm = '', this.credentials});
  factory _AuthConfig.fromJson(Map<String, dynamic> json) =>
      _$AuthConfigFromJson(json);
  final AuthType type;
  final String realm;
  final Map<String, String>? credentials;
  Map<String, dynamic> toJson() => _$AuthConfigToJson(this);

  WebDAVAuthConfig build(BuildContext context) {
    switch (type) {
      case AuthType.none:
        return WebDAVAuthConfig.none;
      case AuthType.basic:
        return WebDAVBasicAuthConfig(
          realm: realm,
          credentials: credentials ?? {},
        );
      default:
        throw BlueprintException(
          context: context,
          'Unsupported WebDAV authentication type: $type',
        );
    }
  }
}

@JsonSerializable()
class _Config {
  _Config({
    required this.backend,
    this.logger,
    this.requestLogger,
    this.authConfig,
    this.address = 'localhost',
    this.port = 8080,
  });

  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String? logger;
  final String? requestLogger;
  final String backend;
  final String address;
  final int port;
  final _AuthConfig? authConfig;

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
      authConfig: authConfig?.build(ctx) ?? WebDAVAuthConfig.none,
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
