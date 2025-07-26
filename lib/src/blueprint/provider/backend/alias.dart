import '../../../abstract/index.dart';
import '../../../backend/alias.dart';
import '../../engine/core.dart';

class _Config {
  _Config({required this.backend, this.subDirectory = '/'});
  factory _Config.fromJson(Map<String, dynamic> json) {
    return _Config(
      backend: json['backend'] as String,
      subDirectory: json['subDirectory'] as String? ?? '/',
    );
  }

  final String backend;
  final String subDirectory;

  Map<String, dynamic> toJson() {
    return {'backend': backend, 'subDirectory': subDirectory};
  }
}

class AliasFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.alias';

  @override
  Future<IFileSystem> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    if (cfg.backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for alias file system',
      );
    }
    final backend = ctx.mustGetComponentByName<IFileSystem>(cfg.backend);
    return AliasFileSystem(
      fileSystem: backend,
      subDirectory: Path.fromString(cfg.subDirectory),
    );
  }
}
