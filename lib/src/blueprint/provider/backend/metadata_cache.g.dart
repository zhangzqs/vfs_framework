// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_cache.dart';

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
      'maxCacheAge',
      'largeDirectoryThreshold',
    ],
  );
  return _Config(
    originBackend: json['originBackend'] as String,
    cacheBackend: json['cacheBackend'] as String,
    cacheDir: json['cacheDir'] as String,
    maxCacheAge: json['maxCacheAge'] == null
        ? const Duration(days: 7)
        : const GoDurationStringConverter().fromJson(
            json['maxCacheAge'] as String,
          ),
    largeDirectoryThreshold:
        (json['largeDirectoryThreshold'] as num?)?.toInt() ?? 1000,
  );
}

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'originBackend': instance.originBackend,
  'cacheBackend': instance.cacheBackend,
  'cacheDir': instance.cacheDir,
  'maxCacheAge': const GoDurationStringConverter().toJson(instance.maxCacheAge),
  'largeDirectoryThreshold': instance.largeDirectoryThreshold,
};
