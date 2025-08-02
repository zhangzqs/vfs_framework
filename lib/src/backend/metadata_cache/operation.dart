import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../abstract/index.dart';
import 'model.dart';

/// 元数据缓存操作类
/// 负责具体的缓存读写、hash计算、目录管理等操作
class MetadataCacheOperation {
  MetadataCacheOperation({
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    this.maxCacheAge = const Duration(minutes: 30),
    this.largeDirectoryThreshold = 1000,
  });

  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final Duration maxCacheAge;
  final int largeDirectoryThreshold;

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(Context context, Path path) {
    final logger = context.logger;
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.trace('Generated hash for ${path.toString()}: $hash');
    return hash;
  }

  /// 在cacheDir中，针对srcPath构建分层缓存目录路径，三层目录结构，有利于文件系统查询性能
  Path _buildCacheMetadataFile(Context context, Path path) {
    final logger = context.logger;
    final hash = _generatePathHash(context, path);
    // 使用前3位作为第一层目录 (每个level1下4096种可能)
    final level1 = hash.substring(0, 3);
    // 使用第4-6位作为第二层目录 (每个level2下4096种可能)
    final level2 = hash.substring(3, 6);
    // 第三级目录使用剩余的hash值
    final level3 = '${hash.substring(6)}.json';
    // 构建分层路径: cacheDir/abc/def/1234ef567890/
    final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

    logger.trace(
      'Built hierarchical cache path for hash $hash: '
      '${hierarchicalPath.toString()}',
    );
    return hierarchicalPath;
  }

  /// 读取缓存的元数据
  Future<MetadataCacheData?> _readCachedMetadata(
    Context context,
    Path path,
  ) async {
    final logger = context.logger;
    try {
      final cacheFilePath = _buildCacheMetadataFile(context, path);

      if (!await cacheFileSystem.exists(context, cacheFilePath)) {
        logger.trace('Cache miss: ${cacheFilePath.toString()}');
        return null;
      }

      final data = await cacheFileSystem.readAsBytes(context, cacheFilePath);
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final cacheData = MetadataCacheData.fromJson(json);

      // 验证缓存是否仍然有效
      if (!cacheData.isValid(
        expectedPath: path.toString(),
        maxAge: maxCacheAge,
      )) {
        logger.trace('Cache expired for ${path.toString()}');
        // 异步删除过期缓存
        unawaited(_invalidateCache(context, path));
        return null;
      }

      logger.trace('Cache hit for ${path.toString()}: ${cacheData.cacheStats}');
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to read cache for ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return null; // 缓存读取失败
    }
  }

  /// 写入缓存的元数据
  Future<void> _writeCachedMetadata(
    Context context,
    Path path,
    MetadataCacheData metadata,
  ) async {
    final logger = context.logger;
    try {
      final cacheFilePath = _buildCacheMetadataFile(context, path);

      // 确保缓存目录存在
      final cacheParentDir = cacheFilePath.parent;
      if (cacheParentDir != null &&
          !await cacheFileSystem.exists(context, cacheParentDir)) {
        await cacheFileSystem.createDirectory(
          context,
          cacheParentDir,
          options: const CreateDirectoryOptions(createParents: true),
        );
      }

      final jsonStr = jsonEncode(metadata.toJson());
      final data = utf8.encode(jsonStr);
      await cacheFileSystem.writeBytes(
        context,
        cacheFilePath,
        Uint8List.fromList(data),
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      logger.trace(
        'Cache written for ${path.toString()}: ${metadata.cacheStats}',
      );
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to write cache for ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 静默处理缓存写入错误
    }
  }

  /// 使缓存失效
  Future<void> _invalidateCache(Context context, Path path) async {
    final logger = context.logger;
    try {
      final cacheFilePath = _buildCacheMetadataFile(context, path);
      if (await cacheFileSystem.exists(context, cacheFilePath)) {
        await cacheFileSystem.delete(context, cacheFilePath);
        logger.trace('Cache invalidated for ${path.toString()}');
      }
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to invalidate cache for ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 静默处理缓存删除错误
    }
  }

  /// 刷新路径的元数据缓存
  Future<MetadataCacheData?> _refreshMetadataCache(
    Context context,
    Path path,
  ) async {
    final logger = context.logger;
    try {
      final status = await originFileSystem.stat(context, path);
      if (status == null) {
        await _invalidateCache(context, path);
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
          await for (final child in originFileSystem.list(context, path)) {
            children.add(child);
            childCount++;

            // 如果子文件数量超过阈值，标记为大目录
            if (childCount > largeDirectoryThreshold) {
              logger.debug(
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
            error: e,
            stackTrace: stackTrace,
          );
          // 列举失败时不缓存子文件列表
        }
      }

      await _writeCachedMetadata(context, path, cacheData);
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to refresh cache for ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 刷新失败时删除缓存
      await _invalidateCache(context, path);
      return null;
    }
  }

  /// 获取文件状态（优先从缓存）
  Future<FileStatus?> getFileStatus(Context context, Path path) async {
    final logger = context.logger;
    try {
      // 首先尝试从缓存读取
      final cachedData = await _readCachedMetadata(context, path);
      if (cachedData != null) {
        return cachedData.stat;
      }

      // 缓存不存在或无效，从原始文件系统获取
      final status = await originFileSystem.stat(context, path);

      // 异步更新缓存
      if (status != null) {
        unawaited(_refreshMetadataCache(context, path));
      }

      return status;
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to get file status for ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 出错时回退到原始文件系统
      return originFileSystem.stat(context, path);
    }
  }

  /// 获取目录列表（优先从缓存）
  Stream<FileStatus> listDirectory(Context context, Path path) async* {
    final logger = context.logger;
    try {
      // 首先尝试从缓存读取
      final cachedData = await _readCachedMetadata(context, path);
      if (cachedData != null && !cachedData.isLargeDirectory) {
        // 普通目录，从缓存读取子文件列表
        final children = cachedData.children;
        if (children != null) {
          logger.trace(
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
      logger.trace(
        'Serving directory listing from origin for ${path.toString()}',
      );
      await for (final item in originFileSystem.list(context, path)) {
        yield item;
      }

      // 异步更新缓存
      unawaited(_refreshMetadataCache(context, path));
    } catch (e, stackTrace) {
      logger.warning(
        'Failed to list directory ${path.toString()}: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 出错时回退到原始文件系统
      await for (final item in originFileSystem.list(context, path)) {
        yield item;
      }
    }
  }

  /// 处理文件系统修改操作后的缓存更新
  Future<void> handleFileSystemChange(
    Context context,
    Path path, {
    bool isDelete = false,
  }) async {
    if (isDelete) {
      // 删除操作：使文件自身的缓存失效
      await _invalidateCache(context, path);
    } else {
      // 创建/修改操作：刷新文件自身的缓存
      await _refreshMetadataCache(context, path);
    }

    // 父目录的子文件列表也需要刷新 - 改为同步等待以确保目录列举的一致性
    final parentPath = path.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(context, parentPath);
    }
  }
}
