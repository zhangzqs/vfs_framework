// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webdav.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_HttpOptions _$HttpOptionsFromJson(Map<String, dynamic> json) => _HttpOptions(
  connectTimeout: json['connectTimeout'] == null
      ? const Duration(seconds: 30)
      : const GoDurationStringConverter().fromJson(
          json['connectTimeout'] as String,
        ),
  receiveTimeout: json['receiveTimeout'] == null
      ? const Duration(seconds: 30)
      : const GoDurationStringConverter().fromJson(
          json['receiveTimeout'] as String,
        ),
  sendTimeout: json['sendTimeout'] == null
      ? const Duration(seconds: 30)
      : const GoDurationStringConverter().fromJson(
          json['sendTimeout'] as String,
        ),
);

Map<String, dynamic> _$HttpOptionsToJson(
  _HttpOptions instance,
) => <String, dynamic>{
  'connectTimeout': const GoDurationStringConverter().toJson(
    instance.connectTimeout,
  ),
  'receiveTimeout': const GoDurationStringConverter().toJson(
    instance.receiveTimeout,
  ),
  'sendTimeout': const GoDurationStringConverter().toJson(instance.sendTimeout),
};

_Config _$ConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const ['baseUrl', 'username', 'password', 'httpOptions'],
  );
  return _Config(
    baseUrl: json['baseUrl'] as String,
    username: json['username'] as String,
    password: json['password'] as String,
    httpOptions: json['httpOptions'] == null
        ? const _HttpOptions()
        : _HttpOptions.fromJson(json['httpOptions'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'baseUrl': instance.baseUrl,
  'username': instance.username,
  'password': instance.password,
  'httpOptions': instance.httpOptions,
};
