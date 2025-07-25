import 'dart:io';

import '../../../abstract/index.dart';
import '../../../backend/index.dart';
import '../../engine/core.dart';

class _Config {
  _Config({required this.baseDir});

  factory _Config.fromJson(Map<String, dynamic> json) {
    return _Config(baseDir: json['baseDir'] as String);
  }

  final String baseDir;
  Map<String, dynamic> toJson() {
    return {'baseDir': baseDir};
  }
}

class LocalFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.local';

  @override
  Future<IFileSystem> createComponent(
    Context ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    if (cfg.baseDir.isEmpty) {
      throw BlueprintException(
        context: ctx,
        'Base directory must be specified for local file system',
      );
    }
    final dir = Directory(cfg.baseDir);
    if (!await dir.exists()) {
      throw BlueprintException(
        context: ctx,
        'Base directory ${cfg.baseDir} does not exist',
      );
    }
    return LocalFileSystem(baseDir: dir);
  }
}
