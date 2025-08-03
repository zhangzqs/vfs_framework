import 'dart:async';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';

import '../../../logger/index.dart';
import '../../engine/core.dart';

part 'logger.g.dart';

@JsonSerializable(disallowUnrecognizedKeys: true)
class _LogLocalFileConfig {
  _LogLocalFileConfig({
    required this.logDir,
    this.maxFileSize = 512 * 1024 * 1024, // 512 MB
    this.maxFileCount = 5,
  });

  factory _LogLocalFileConfig.fromJson(Map<String, dynamic> json) =>
      _$LogLocalFileConfigFromJson(json);
  final String logDir;
  final int maxFileSize; // 单个日志文件的最大大小，单位为字
  final int maxFileCount; // 最大日志文件数量
  Map<String, dynamic> toJson() => _$LogLocalFileConfigToJson(this);

  StreamSink<String> buildSink() {
    // 创建一个文本文件日志接收器
    return TextFileSink(
      Directory(logDir),
      maxFileSize: maxFileSize,
      maxFiles: maxFileCount,
    );
  }
}

enum LogFormat { text, json }

@JsonSerializable(disallowUnrecognizedKeys: true)
class _Config {
  _Config({
    this.localLogFile,
    this.level = Level.debug,
    this.format = LogFormat.json,
    this.codeFilenameEnabled = true,
    this.metadata = const {},
  });
  factory _Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  final _LogLocalFileConfig? localLogFile;
  final Level level;
  final bool codeFilenameEnabled;
  final Map<String, dynamic> metadata;
  final LogFormat format;
  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  Logger build(BuildContext ctx) {
    final textSink = localLogFile?.buildSink() ?? TextConsoleSink();
    final logRecordAdapter = switch (format) {
      LogFormat.text => LogRecordTextAdapter(textSink),
      LogFormat.json => LogRecordJsonAdapter(textSink),
    };
    return Logger(
      logRecordAdapter,
      level: level,
      sourceFilenameEnabled: codeFilenameEnabled,
      metadata: metadata,
    );
  }
}

class LoggerProvider extends ComponentProvider<Logger> {
  @override
  String get type => 'logger.logger';

  @override
  Future<Logger> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = _Config.fromJson(config);
    return cfg.build(ctx);
  }

  @override
  Future<void> close(BuildContext ctx, Logger component) async {
    await component.close();
  }
}
