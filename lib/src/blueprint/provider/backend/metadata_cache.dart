import 'package:json_annotation/json_annotation.dart';
import 'package:vfs_framework/src/backend/index.dart';
import 'package:vfs_framework/src/helper/go_duration_helper.dart';

import '../../../abstract/index.dart';
import '../../engine/index.dart';

part 'metadata_cache.g.dart';

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({
    required this.originBackend,
    required this.cacheBackend,
    required this.cacheDir,
    this.maxCacheAge = const Duration(days: 7),
    this.largeDirectoryThreshold = 1000,
  });
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  final String originBackend;
  final String cacheBackend;
  final String cacheDir;

  @GoDurationStringConverter()
  final Duration maxCacheAge;

  final int largeDirectoryThreshold;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  MetadataCacheFileSystem build(BuildContext ctx) {
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
      maxCacheAge: maxCacheAge,
      largeDirectoryThreshold: largeDirectoryThreshold,
    );
  }
}

class MetadataCacheFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.metadata_cache';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }
}
