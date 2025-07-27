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

  Runner build(Context ctx) {
    if (backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for HTTP file system',
      );
    }
    return Runner(
      fs: ctx.mustGetComponentByName<IFileSystem>(backend),
      address: address,
      port: port,
    );
  }
}

class Runner {
  const Runner({required this.fs, required this.address, required this.port});

  final IFileSystem fs;
  final String address;
  final int port;

  Future<void> run() async {
    final server = HttpServer(fs);
    await server.start(address, port);
  }
}

class HttpServerProvider extends ComponentProvider<Runner> {
  @override
  String get type => 'frontend.http';

  @override
  Future<Runner> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }

  @override
  bool get isRunnable => true;

  @override
  Future<void> runComponent(Context ctx, Runner component) async {
    await component.run();
  }
}
