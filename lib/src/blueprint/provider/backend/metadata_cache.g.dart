// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_cache.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Config _$ConfigFromJson(Map<String, dynamic> json) => _Config(
  originBackend: json['originBackend'] as String,
  cacheBackend: json['cacheBackend'] as String,
  cacheDir: json['cacheDir'] as String,
);

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'originBackend': instance.originBackend,
  'cacheBackend': instance.cacheBackend,
  'cacheDir': instance.cacheDir,
};
