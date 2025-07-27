import 'package:json_annotation/json_annotation.dart';

import '../../../abstract/index.dart';
import '../../../backend/index.dart';
import '../../engine/core.dart';

part 'union.g.dart';

@JsonSerializable()
class _ItemConfig {
  _ItemConfig({
    required this.backend,
    required this.mountPath,
    this.readOnly = false,
    this.priority = 0,
  });
  factory _ItemConfig.fromJson(Map<String, dynamic> json) =>
      _$ItemConfigFromJson(json);

  final String backend;
  final String mountPath;
  final bool readOnly;
  final int priority;

  Map<String, dynamic> toJson() => _$ItemConfigToJson(this);

  UnionFileSystemItem build(Context ctx) {
    return UnionFileSystemItem(
      fileSystem: ctx.mustGetComponentByName<IFileSystem>(backend),
      mountPath: Path.fromString(mountPath),
      readOnly: readOnly,
      priority: priority,
    );
  }
}

@JsonSerializable()
class _Config {
  _Config({required this.items});
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final List<_ItemConfig> items;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  List<UnionFileSystemItem> build(Context ctx) {
    return items.map((item) => item.build(ctx)).toList();
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
    return UnionFileSystem(cfg.build(ctx));
  }
}
