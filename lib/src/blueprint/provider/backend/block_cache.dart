import '../../../../vfs_framework.dart';
import '../../../backend/block_cache.dart';
import '../../index.dart';

class _Config {
  _Config({
    required this.originBackend,
    required this.cacheBackend,
    required this.cacheDir,
    this.blockSize = 4 * 1024 * 1024,
  });
  factory _Config.fromJson(Map<String, dynamic> json) {
    return _Config(
      originBackend: json['originBackend'] as String,
      cacheBackend: json['cacheBackend'] as String,
      cacheDir: json['cacheDir'] as String,
      blockSize: json['blockSize'] as int? ?? 4 * 1024 * 1024, // 默认4MB
    );
  }
  final String originBackend;
  final String cacheBackend;
  final String cacheDir;
  final int blockSize;

  Map<String, dynamic> toJson() {
    return {
      'originBackend': originBackend,
      'cacheBackend': cacheBackend,
      'cacheDir': cacheDir,
      'blockSize': blockSize,
    };
  }

  BlockCacheFileSystem buildBlockCache(Context ctx) {
    if (originBackend.isEmpty || cacheBackend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Both upstream and cache backends must be specified for block cache file system',
      );
    }
    final upstream = ctx.mustGetComponentByName<IFileSystem>(originBackend);
    final cache = ctx.mustGetComponentByName<IFileSystem>(cacheBackend);
    return BlockCacheFileSystem(
      originFileSystem: upstream,
      cacheFileSystem: cache,
      cacheDir: Path.fromString(cacheDir),
      blockSize: blockSize,
    );
  }
}

class BlockCacheFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.block_cache';

  @override
  Future<IFileSystem> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);

    return cfg.buildBlockCache(ctx);
  }
}
