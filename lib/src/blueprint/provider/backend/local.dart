import 'dart:io';

import 'package:json_annotation/json_annotation.dart';

import '../../../abstract/index.dart';
import '../../../backend/index.dart';
import '../../engine/core.dart';

part 'local.g.dart';

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({required this.baseDir});

  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String baseDir;
  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  Future<LocalFileSystem> build(BuildContext ctx) async {
    if (baseDir.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Base directory must be specified for local file system',
      );
    }
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      throw BlueprintException(
        context: ctx,
        'Base directory $baseDir does not exist',
      );
    }
    return LocalFileSystem(baseDir: dir);
  }
}

class LocalFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.local';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return await cfg.build(ctx);
  }
}
