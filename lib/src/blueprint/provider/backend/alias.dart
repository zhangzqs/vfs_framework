import 'package:json_annotation/json_annotation.dart';

import '../../../abstract/index.dart';
import '../../../backend/alias.dart';
import '../../engine/core.dart';

part 'alias.g.dart';

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({required this.backend, this.subDirectory = '/'});
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String backend;
  final String subDirectory;

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  AliasFileSystem build(BuildContext ctx) {
    if (backend.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Backend must be specified for alias file system',
      );
    }
    return AliasFileSystem(
      fileSystem: ctx.mustGetComponentByName<IFileSystem>(backend),
      subDirectory: Path.fromString(subDirectory),
    );
  }
}

class AliasFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.alias';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }
}
