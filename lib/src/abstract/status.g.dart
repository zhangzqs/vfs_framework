// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileStatus _$FileStatusFromJson(Map<String, dynamic> json) => FileStatus(
  isDirectory: json['isDirectory'] as bool,
  path: const PathJsonConverter().fromJson(json['path'] as String),
  size: (json['size'] as num?)?.toInt(),
  mimeType: json['mimeType'] as String?,
);

Map<String, dynamic> _$FileStatusToJson(FileStatus instance) =>
    <String, dynamic>{
      'path': const PathJsonConverter().toJson(instance.path),
      'size': instance.size,
      'isDirectory': instance.isDirectory,
      'mimeType': instance.mimeType,
    };
