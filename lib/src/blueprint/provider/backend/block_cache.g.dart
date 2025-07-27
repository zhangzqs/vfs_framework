// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block_cache.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Config _$ConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const [
      'originBackend',
      'cacheBackend',
      'cacheDir',
      'blockSize',
      'readAheadBlocks',
      'enableReadAhead',
    ],
  );
  return _Config(
    originBackend: json['originBackend'] as String,
    cacheBackend: json['cacheBackend'] as String,
    cacheDir: json['cacheDir'] as String,
    blockSize: (json['blockSize'] as num?)?.toInt() ?? 1024 * 1024,
    readAheadBlocks: (json['readAheadBlocks'] as num?)?.toInt() ?? 2,
    enableReadAhead: json['enableReadAhead'] as bool? ?? true,
  );
}

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'originBackend': instance.originBackend,
  'cacheBackend': instance.cacheBackend,
  'cacheDir': instance.cacheDir,
  'blockSize': instance.blockSize,
  'readAheadBlocks': instance.readAheadBlocks,
  'enableReadAhead': instance.enableReadAhead,
};
