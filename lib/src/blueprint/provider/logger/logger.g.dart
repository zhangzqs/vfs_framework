// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LogLocalFileConfig _$LogLocalFileConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const ['logDir', 'maxFileSize', 'maxFileCount'],
  );
  return _LogLocalFileConfig(
    logDir: json['logDir'] as String,
    maxFileSize: (json['maxFileSize'] as num?)?.toInt() ?? 512 * 1024 * 1024,
    maxFileCount: (json['maxFileCount'] as num?)?.toInt() ?? 5,
  );
}

Map<String, dynamic> _$LogLocalFileConfigToJson(_LogLocalFileConfig instance) =>
    <String, dynamic>{
      'logDir': instance.logDir,
      'maxFileSize': instance.maxFileSize,
      'maxFileCount': instance.maxFileCount,
    };

_Config _$ConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const [
      'localLogFile',
      'level',
      'codeFilenameEnabled',
      'metadata',
      'format',
    ],
  );
  return _Config(
    localLogFile: json['localLogFile'] == null
        ? null
        : _LogLocalFileConfig.fromJson(
            json['localLogFile'] as Map<String, dynamic>,
          ),
    level: $enumDecodeNullable(_$LevelEnumMap, json['level']) ?? Level.debug,
    format:
        $enumDecodeNullable(_$LogFormatEnumMap, json['format']) ??
        LogFormat.json,
    codeFilenameEnabled: json['codeFilenameEnabled'] as bool? ?? true,
    metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
  );
}

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'localLogFile': instance.localLogFile,
  'level': _$LevelEnumMap[instance.level]!,
  'codeFilenameEnabled': instance.codeFilenameEnabled,
  'metadata': instance.metadata,
  'format': _$LogFormatEnumMap[instance.format]!,
};

const _$LevelEnumMap = {
  Level.trace: 'trace',
  Level.debug: 'debug',
  Level.info: 'info',
  Level.warning: 'warning',
  Level.error: 'error',
};

const _$LogFormatEnumMap = {LogFormat.text: 'text', LogFormat.json: 'json'};
