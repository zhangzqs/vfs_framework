import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../abstract/index.dart';

part 'model.g.dart';

const _currentVersion = '1.0';

/// 元数据缓存数据类
/// 用于存储文件或目录的缓存元数据信息
@JsonSerializable()
class MetadataCacheData extends Equatable {
  const MetadataCacheData({
    required this.path,
    required this.stat,
    required this.lastUpdated,
    this.children,
    this.isLargeDirectory = false,
    this.version = _currentVersion,
  });

  factory MetadataCacheData.fromJson(Map<String, dynamic> json) =>
      _$MetadataCacheDataFromJson(json);

  /// 文件路径
  final String path;

  /// 文件状态信息
  final FileStatus stat;

  /// 最后更新时间戳
  final DateTime lastUpdated;

  /// 子文件列表（仅目录有效，大目录为null）
  final List<FileStatus>? children;

  /// 是否为大目录（不缓存子文件列表）
  final bool isLargeDirectory;

  /// 元数据版本
  final String version;

  Map<String, dynamic> toJson() => _$MetadataCacheDataToJson(this);

  /// 检查缓存是否仍然有效
  bool isValid({
    required String expectedPath,
    Duration maxAge = const Duration(minutes: 30),
  }) {
    final now = DateTime.now();
    final age = now.difference(lastUpdated);

    return path == expectedPath && version == _currentVersion && age <= maxAge;
  }

  /// 创建一个更新了时间戳的新实例
  MetadataCacheData updateTimestamp() {
    return MetadataCacheData(
      path: path,
      stat: stat,
      lastUpdated: DateTime.now(),
      children: children,
      isLargeDirectory: isLargeDirectory,
      version: version,
    );
  }

  /// 更新子文件列表
  MetadataCacheData updateChildren(List<FileStatus> newChildren) {
    return MetadataCacheData(
      path: path,
      stat: stat,
      lastUpdated: DateTime.now(),
      children: newChildren,
      isLargeDirectory: false,
      version: version,
    );
  }

  /// 标记为大目录
  MetadataCacheData markAsLargeDirectory() {
    return MetadataCacheData(
      path: path,
      stat: stat,
      lastUpdated: DateTime.now(),
      children: null,
      isLargeDirectory: true,
      version: version,
    );
  }

  /// 获取缓存统计信息
  String get cacheStats {
    if (stat.isDirectory) {
      if (isLargeDirectory) {
        return '大目录（子文件未缓存）';
      } else {
        final childCount = children?.length ?? 0;
        return '目录，已缓存 $childCount 个子文件';
      }
    } else {
      return '文件元数据已缓存';
    }
  }

  @override
  String toString() => toJson().toString();

  @override
  List<Object?> get props => [
    path,
    stat,
    lastUpdated,
    children,
    isLargeDirectory,
    version,
  ];
}
