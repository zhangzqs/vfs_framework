import '../../../abstract/index.dart';
import '../../../frontend/http.dart';
import '../../engine/core.dart';

class _Config {
  _Config({required this.backend});
  factory _Config.fromJson(Map<String, dynamic> json) {
    return _Config(backend: json['backend'] as String);
  }
  final String backend;

  Map<String, dynamic> toJson() {
    return {'backend': backend};
  }

  IFileSystem build(Context ctx) {
    if (backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for HTTP file system',
      );
    }
    return ctx.mustGetComponentByName<IFileSystem>(backend);
  }
}

class HttpServerProvider extends ComponentProvider<HttpServer> {
  @override
  String get type => 'frontend.http';

  @override
  Future<HttpServer> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return HttpServer(cfg.build(ctx));
  }

  @override
  bool get isRunnable => true;

  @override
  Future<void> runComponent(Context ctx, HttpServer component) async {
    await component.start('0.0.0.0', 28080);
  }
}
