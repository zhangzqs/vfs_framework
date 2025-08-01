// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CacheMetadata _$CacheMetadataFromJson(Map<String, dynamic> json) =>
    CacheMetadata(
      filePath: json['filePath'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      blockSize: (json['blockSize'] as num).toInt(),
      totalBlocks: (json['totalBlocks'] as num).toInt(),
      cachedBlocks: (json['cachedBlocks'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toSet(),
      lastModified: DateTime.parse(json['lastModified'] as String),
      version: json['version'] as String? ?? _currentVersion,
    );

Map<String, dynamic> _$CacheMetadataToJson(CacheMetadata instance) =>
    <String, dynamic>{
      'filePath': instance.filePath,
      'fileSize': instance.fileSize,
      'blockSize': instance.blockSize,
      'totalBlocks': instance.totalBlocks,
      'cachedBlocks': instance.cachedBlocks.toList(),
      'lastModified': instance.lastModified.toIso8601String(),
      'version': instance.version,
    };
