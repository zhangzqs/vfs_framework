import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import '../../abstract/index.dart';
import 'model.dart';

/// 元数据缓存操作类
/// 负责具体的缓存读写、hash计算、目录管理等操作
class MetadataCacheOperation {
  MetadataCacheOperation({
    required this.logger,
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    this.maxCacheAge = const Duration(minutes: 30),
    this.largeDirectoryThreshold = 1000,
  });

  final Logger logger;
  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final Duration maxCacheAge;
  final int largeDirectoryThreshold;

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(Path path) {
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.finest('Generated hash for ${path.toString()}: $hash');
    return hash;
  }

  /// 在cacheDir中，针对srcPath构建分层缓存目录路径，三层目录结构，有利于文件系统查询性能
  Path _buildCacheMetadataFile(Path path) {
    final hash = _generatePathHash(path);
    // 使用前3位作为第一层目录 (每个level1下4096种可能)
    final level1 = hash.substring(0, 3);
    // 使用第4-6位作为第二层目录 (每个level2下4096种可能)
    final level2 = hash.substring(3, 6);
    // 第三级目录使用剩余的hash值
    final level3 = '${hash.substring(6)}.json';
    // 构建分层路径: cacheDir/abc/def/1234ef567890/
    final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

    logger.finest(
      'Built hierarchical cache path for hash $hash: '
      '${hierarchicalPath.toString()}',
    );
    return hierarchicalPath;
  }

  /// 读取缓存的元数据
  Future<MetadataCacheData?> _readCachedMetadata(Path path) async {
    try {
      final cacheFilePath = _buildCacheMetadataFile(path);

      if (!await cacheFileSystem.exists(cacheFilePath)) {
        logger.finest('Cache miss: ${cacheFilePath.toString()}');
        return null;
      }

      final data = await cacheFileSystem.readAsBytes(cacheFilePath);
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final cacheData = MetadataCacheData.fromJson(json);

      // 验证缓存是否仍然有效
      if (!cacheData.isValid(
        expectedPath: path.toString(),
        maxAge: maxCacheAge,
      )) {
        logger.finest('Cache expired for ${path.toString()}');
        // 异步删除过期缓存
        unawaited(_invalidateCache(path));
        return null;
      }

      logger.finest(
        'Cache hit for ${path.toString()}: ${cacheData.cacheStats}',
      );
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to read cache for ${path.toString()}: $e',
        e,
        stackTrace,
      );
      return null; // 缓存读取失败
    }
  }

  /// 写入缓存的元数据
  Future<void> _writeCachedMetadata(
    Path path,
    MetadataCacheData metadata,
  ) async {
    try {
      final cacheFilePath = _buildCacheMetadataFile(path);

      // 确保缓存目录存在
      final cacheParentDir = cacheFilePath.parent;
      if (cacheParentDir != null &&
          !await cacheFileSystem.exists(cacheParentDir)) {
        await cacheFileSystem.createDirectory(
          cacheParentDir,
          options: const CreateDirectoryOptions(createParents: true),
        );
      }

      final jsonStr = jsonEncode(metadata.toJson());
      final data = utf8.encode(jsonStr);
      await cacheFileSystem.writeBytes(
        cacheFilePath,
        Uint8List.fromList(data),
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      logger.finest(
        'Cache written for ${path.toString()}: ${metadata.cacheStats}',
      );
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to write cache for ${path.toString()}: $e',
        e,
        stackTrace,
      );
      // 静默处理缓存写入错误
    }
  }

  /// 使缓存失效
  Future<void> _invalidateCache(Path path) async {
    try {
      final cacheFilePath = _buildCacheMetadataFile(path);
      if (await cacheFileSystem.exists(cacheFilePath)) {
        await cacheFileSystem.delete(cacheFilePath);
        logger.finest('Cache invalidated for ${path.toString()}');
      }
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to invalidate cache for ${path.toString()}: $e',
        e,
        stackTrace,
      );
      // 静默处理缓存删除错误
    }
  }

  /// 刷新路径的元数据缓存
  Future<MetadataCacheData?> _refreshMetadataCache(Path path) async {
    try {
      final status = await originFileSystem.stat(path);
      if (status == null) {
        await _invalidateCache(path);
        return null;
      }

      // 基本元数据
      var cacheData = MetadataCacheData(
        path: path.toString(),
        stat: status,
        lastUpdated: DateTime.now(),
      );

      // 如果是目录，根据策略决定是否缓存子文件列表
      if (status.isDirectory) {
        final children = <FileStatus>[];
        var childCount = 0;

        try {
          await for (final child in originFileSystem.list(path)) {
            children.add(child);
            childCount++;

            // 如果子文件数量超过阈值，标记为大目录
            if (childCount > largeDirectoryThreshold) {
              logger.fine(
                'Directory ${path.toString()} has $childCount children, '
                'marking as large directory',
              );
              cacheData = cacheData.markAsLargeDirectory();
              break;
            }
          }

          if (!cacheData.isLargeDirectory) {
            cacheData = cacheData.updateChildren(children);
          }
        } catch (e, stackTrace) {
          logger.warning(
            'Failed to list directory ${path.toString()}: $e',
            e,
            stackTrace,
          );
          // 列举失败时不缓存子文件列表
        }
      }

      await _writeCachedMetadata(path, cacheData);
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to refresh cache for ${path.toString()}: $e',
        e,
        stackTrace,
      );
      // 刷新失败时删除缓存
      await _invalidateCache(path);
      return null;
    }
  }

  /// 获取文件状态（优先从缓存）
  Future<FileStatus?> getFileStatus(Path path) async {
    try {
      // 首先尝试从缓存读取
      final cachedData = await _readCachedMetadata(path);
      if (cachedData != null) {
        return cachedData.stat;
      }

      // 缓存不存在或无效，从原始文件系统获取
      final status = await originFileSystem.stat(path);

      // 异步更新缓存
      if (status != null) {
        unawaited(_refreshMetadataCache(path));
      }

      return status;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to get file status for ${path.toString()}: $e',
        e,
        stackTrace,
      );
      // 出错时回退到原始文件系统
      return originFileSystem.stat(path);
    }
  }

  /// 获取目录列表（优先从缓存）
  Stream<FileStatus> listDirectory(Path path) async* {
    try {
      // 首先尝试从缓存读取
      final cachedData = await _readCachedMetadata(path);
      if (cachedData != null && !cachedData.isLargeDirectory) {
        // 普通目录，从缓存读取子文件列表
        final children = cachedData.children;
        if (children != null) {
          logger.finest(
            'Serving directory listing from cache for ${path.toString()}: '
            '${children.length} items',
          );
          for (final child in children) {
            yield child;
          }
          return;
        }
      }

      // 缓存不存在、无效或是大目录，从原始文件系统获取
      logger.finest(
        'Serving directory listing from origin for ${path.toString()}',
      );
      await for (final item in originFileSystem.list(path)) {
        yield item;
      }

      // 异步更新缓存
      unawaited(_refreshMetadataCache(path));
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to list directory ${path.toString()}: $e',
        e,
        stackTrace,
      );
      // 出错时回退到原始文件系统
      await for (final item in originFileSystem.list(path)) {
        yield item;
      }
    }
  }

  /// 处理文件系统修改操作后的缓存更新
  Future<void> handleFileSystemChange(
    Path path, {
    bool isDelete = false,
  }) async {
    if (isDelete) {
      // 删除操作：使文件自身的缓存失效
      await _invalidateCache(path);
    } else {
      // 创建/修改操作：刷新文件自身的缓存
      await _refreshMetadataCache(path);
    }

    // 父目录的子文件列表也需要刷新 - 改为同步等待以确保目录列举的一致性
    final parentPath = path.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(parentPath);
    }
  }
}
