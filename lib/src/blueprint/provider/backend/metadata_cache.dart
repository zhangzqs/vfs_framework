import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/backend/index.dart';

import '../../../abstract/index.dart';
import '../../engine/index.dart';

part 'metadata_cache.g.dart';

@JsonSerializable()
class _Config {
  _Config({
    required this.originBackend,
    required this.cacheBackend,
    required this.cacheDir,
  });
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  final String originBackend;
  final String cacheBackend;
  final String cacheDir;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  MetadataCacheFileSystem build(Context ctx) {
    if (originBackend.isEmpty || cacheBackend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Both upstream and cache backends must be specified for '
        'block cache file system',
      );
    }
    final upstream = ctx.mustGetComponentByName<IFileSystem>(originBackend);
    final cache = ctx.mustGetComponentByName<IFileSystem>(cacheBackend);
    return MetadataCacheFileSystem(
      originFileSystem: upstream,
      cacheFileSystem: cache,
      cacheDir: Path.fromString(cacheDir),
    );
  }
}

class MetadataCacheFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.metadata_cache';

  @override
  Future<IFileSystem> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }
}
