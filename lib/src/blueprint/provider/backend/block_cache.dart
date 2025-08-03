import 'package:json_annotation/json_annotation.dart';

import '../../../../vfs_framework.dart';

part 'block_cache.g.dart';

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({
    required this.originBackend,
    required this.cacheBackend,
    required this.cacheDir,
    this.blockSize = 1024 * 1024,
    this.readAheadBlocks = 2,
    this.enableReadAhead = true,
  });
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  final String originBackend;
  final String cacheBackend;
  final String cacheDir;
  final int blockSize;
  final int readAheadBlocks;
  final bool enableReadAhead;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  BlockCacheFileSystem build(BuildContext ctx) {
    if (originBackend.isEmpty || cacheBackend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Both upstream and cache backends must be specified for '
        'block cache file system',
      );
    }
    final upstream = ctx.mustGetComponentByName<IFileSystem>(originBackend);
    final cache = ctx.mustGetComponentByName<IFileSystem>(cacheBackend);
    return BlockCacheFileSystem(
      originFileSystem: upstream,
      cacheFileSystem: cache,
      cacheDir: Path.fromString(cacheDir),
      blockSize: blockSize,
      readAheadBlocks: readAheadBlocks,
      enableReadAhead: enableReadAhead,
    );
  }
}

class BlockCacheFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.block_cache';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);

    return cfg.build(ctx);
  }
}
