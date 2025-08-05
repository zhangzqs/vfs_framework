// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webdav.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AuthConfig _$AuthConfigFromJson(Map<String, dynamic> json) => _AuthConfig(
  type: $enumDecodeNullable(_$AuthTypeEnumMap, json['type']) ?? AuthType.none,
  realm: json['realm'] as String? ?? '',
  credentials: (json['credentials'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
);

Map<String, dynamic> _$AuthConfigToJson(_AuthConfig instance) =>
    <String, dynamic>{
      'type': _$AuthTypeEnumMap[instance.type]!,
      'realm': instance.realm,
      'credentials': instance.credentials,
    };

const _$AuthTypeEnumMap = {
  AuthType.none: 'none',
  AuthType.basic: 'basic',
  AuthType.bearer: 'bearer',
  AuthType.digest: 'digest',
};

_Config _$ConfigFromJson(Map<String, dynamic> json) => _Config(
  backend: json['backend'] as String,
  logger: json['logger'] as String?,
  requestLogger: json['requestLogger'] as String?,
  authConfig: json['authConfig'] == null
      ? null
      : _AuthConfig.fromJson(json['authConfig'] as Map<String, dynamic>),
  address: json['address'] as String? ?? 'localhost',
  port: (json['port'] as num?)?.toInt() ?? 8080,
);

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'logger': instance.logger,
  'requestLogger': instance.requestLogger,
  'backend': instance.backend,
  'address': instance.address,
  'port': instance.port,
  'authConfig': instance.authConfig,
};
