import '../../../abstract/index.dart';
import '../../../backend/index.dart';
import '../../engine/core.dart';

class _ItemConfig {
  _ItemConfig({
    required this.backend,
    required this.mountPath,
    this.readOnly = false,
    this.priority = 0,
  });
  factory _ItemConfig.fromJson(Map<String, dynamic> json) {
    return _ItemConfig(
      backend: json['backend'] as String,
      mountPath: json['mountPath'] as String,
      readOnly: json['readOnly'] as bool? ?? false,
      priority: json['priority'] as int? ?? 0,
    );
  }

  final String backend;
  final String mountPath;
  final bool readOnly;
  final int priority;

  Map<String, dynamic> toJson() {
    return {
      'backend': backend,
      'mountPath': mountPath,
      'readOnly': readOnly,
      'priority': priority,
    };
  }

  UnionFileSystemItem buildItem(Context ctx) {
    return UnionFileSystemItem(
      fileSystem: ctx.mustGetComponentByName<IFileSystem>(backend),
      mountPath: Path.fromString(mountPath),
      readOnly: readOnly,
      priority: priority,
    );
  }
}

class _Config {
  _Config({required this.items});
  factory _Config.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>)
        .map((item) => _ItemConfig.fromJson(item as Map<String, dynamic>))
        .toList();
    return _Config(items: items);
  }

  final List<_ItemConfig> items;

  Map<String, dynamic> toJson() {
    return {'items': items.map((item) => item.toJson()).toList()};
  }

  List<UnionFileSystemItem> buildItems(Context ctx) {
    return items.map((item) => item.buildItem(ctx)).toList();
  }
}

class UnionFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.union';

  @override
  Future<IFileSystem> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return UnionFileSystem(cfg.buildItems(ctx));
  }
}
