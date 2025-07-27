// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'union.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ItemConfig _$ItemConfigFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const ['backend', 'mountPath', 'readOnly', 'priority'],
  );
  return _ItemConfig(
    backend: json['backend'] as String,
    mountPath: json['mountPath'] as String,
    readOnly: json['readOnly'] as bool? ?? false,
    priority: (json['priority'] as num?)?.toInt() ?? 0,
  );
}

Map<String, dynamic> _$ItemConfigToJson(_ItemConfig instance) =>
    <String, dynamic>{
      'backend': instance.backend,
      'mountPath': instance.mountPath,
      'readOnly': instance.readOnly,
      'priority': instance.priority,
    };

_Config _$ConfigFromJson(Map<String, dynamic> json) => _Config(
  items: (json['items'] as List<dynamic>)
      .map((e) => _ItemConfig.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ConfigToJson(_Config instance) => <String, dynamic>{
  'items': instance.items,
};
