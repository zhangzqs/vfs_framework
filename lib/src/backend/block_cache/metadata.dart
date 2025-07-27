import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'metadata.g.dart';

const _currentVersion = '1.0';

/// 块缓存元数据类
/// 用于存储缓存文件的相关信息，包括原文件路径、大小、块信息等
@JsonSerializable()
class CacheMetadata extends Equatable {
  const CacheMetadata({
    required this.filePath,
    required this.fileSize,
    required this.blockSize,
    required this.totalBlocks,
    required this.cachedBlocks,
    required this.lastModified,
    this.version = _currentVersion,
  });
  factory CacheMetadata.fromJson(Map<String, dynamic> json) =>
      _$CacheMetadataFromJson(json);

  /// 原文件路径
  final String filePath;

  /// 原文件大小（字节）
  final int fileSize;

  /// 块大小（字节）
  final int blockSize;

  /// 总块数
  final int totalBlocks;

  /// 已缓存的块索引列表（有序）
  final Set<int> cachedBlocks;

  /// 最后修改时间戳
  final DateTime lastModified;

  /// 元数据版本
  final String version;

  /// 从JSON创建CacheMetadata实例

  Map<String, dynamic> toJson() => _$CacheMetadataToJson(this);

  /// 创建一个新的CacheMetadata，添加一个新的缓存块
  CacheMetadata addCachedBlock(int blockIdx) {
    final updatedBlocks = Set<int>.from(cachedBlocks);
    if (!updatedBlocks.contains(blockIdx)) {
      updatedBlocks.add(blockIdx);
    }

    return CacheMetadata(
      filePath: filePath,
      fileSize: fileSize,
      blockSize: blockSize,
      totalBlocks: totalBlocks,
      cachedBlocks: updatedBlocks,
      lastModified: DateTime.now(),
      version: version,
    );
  }

  /// 检查指定块是否已缓存
  bool isBlockCached(int blockIdx) {
    return cachedBlocks.contains(blockIdx);
  }

  /// 获取缓存完成度（0.0 - 1.0）
  double get cacheCompleteness {
    if (totalBlocks == 0) return 1.0;
    return cachedBlocks.length / totalBlocks;
  }

  /// 获取缓存大小统计信息
  String get cacheStats {
    return '${cachedBlocks.length}/$totalBlocks blocks cached '
        '(${(cacheCompleteness * 100).toStringAsFixed(1)}%)';
  }

  /// 验证元数据是否与当前文件信息匹配
  bool isValid({
    required String expectedPath,
    required int expectedFileSize,
    required int expectedBlockSize,
  }) {
    return filePath == expectedPath &&
        fileSize == expectedFileSize &&
        blockSize == expectedBlockSize &&
        version == _currentVersion;
  }

  @override
  String toString() => toJson().toString();

  @override
  List<Object?> get props => [
    filePath,
    fileSize,
    blockSize,
    totalBlocks,
    cachedBlocks,
    lastModified,
    version,
  ];
}
