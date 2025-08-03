// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webdav.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Config _$ConfigFromJson(Map<String, dynamic> json) => _Config(
  backend: json['backend'] as String,
  logger: json['logger'] as String?,
  requestLogger: json['requestLogger'] as String?,
  address: json['address'] as String? ?? 'localhost',
  port: (json['port'] as num?)?.toInt() ?? 8080,
);

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'logger': instance.logger,
  'requestLogger': instance.requestLogger,
  'backend': instance.backend,
  'address': instance.address,
  'port': instance.port,
};
