// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_cache_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MetadataCacheData _$MetadataCacheDataFromJson(Map<String, dynamic> json) =>
    MetadataCacheData(
      path: json['path'] as String,
      stat: FileStatus.fromJson(json['stat'] as Map<String, dynamic>),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      children: (json['children'] as List<dynamic>?)
          ?.map((e) => FileStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
      isLargeDirectory: json['isLargeDirectory'] as bool? ?? false,
      version: json['version'] as String? ?? _currentVersion,
    );

Map<String, dynamic> _$MetadataCacheDataToJson(MetadataCacheData instance) =>
    <String, dynamic>{
      'path': instance.path,
      'stat': instance.stat,
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'children': instance.children,
      'isLargeDirectory': instance.isLargeDirectory,
      'version': instance.version,
    };
