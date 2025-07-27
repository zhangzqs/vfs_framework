// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alias.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Config _$ConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(json, allowedKeys: const ['backend', 'subDirectory']);
  return _Config(
    backend: json['backend'] as String,
    subDirectory: json['subDirectory'] as String? ?? '/',
  );
}

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'backend': instance.backend,
  'subDirectory': instance.subDirectory,
};
