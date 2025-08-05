import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../abstract/index.dart';
import 'model.dart';

/// 缓存存储管理器，负责底层缓存文件的读写操作
class _CacheStorageManager {
  _CacheStorageManager({required this.cacheFileSystem, required this.cacheDir});

  final IFileSystem cacheFileSystem;
  final Path cacheDir;

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(Context context, Path path) {
    final logger = context.logger;
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.trace(
      '为路径生成哈希值',
      metadata: {
        'path': pathString,
        'hash': hash,
        'operation': 'generate_path_hash',
      },
    );
    return hash;
  }

  /// 构建缓存文件路径，三层目录结构，有利于文件系统查询性能
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
      '构建分层缓存路径',
      metadata: {
        'path': path.toString(),
        'hash': hash,
        'cache_path': hierarchicalPath.toString(),
        'level1': level1,
        'level2': level2,
        'level3': level3,
        'operation': 'build_cache_path',
      },
    );
    return hierarchicalPath;
  }

  /// 读取缓存文件
  Future<MetadataCacheData?> readCache(Context context, Path path) async {
    final logger = context.logger;
    try {
      final cacheFilePath = _buildCacheMetadataFile(context, path);

      if (!await cacheFileSystem.exists(context, cacheFilePath)) {
        logger.trace(
          '缓存未命中',
          metadata: {
            'path': path.toString(),
            'cache_path': cacheFilePath.toString(),
            'operation': 'cache_miss',
          },
        );
        return null;
      }

      final data = await cacheFileSystem.readAsBytes(context, cacheFilePath);
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final cacheData = MetadataCacheData.fromJson(json);

      logger.trace(
        '缓存读取成功',
        metadata: {
          'path': path.toString(),
          'cache_stats': cacheData.cacheStats,
          'last_updated': cacheData.lastUpdated.toIso8601String(),
          'operation': 'cache_read_success',
        },
      );
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        '缓存读取失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {'path': path.toString(), 'operation': 'read_cache_failed'},
      );
      return null; // 缓存读取失败
    }
  }

  /// 写入缓存文件
  Future<void> writeCache(
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
        '缓存写入成功',
        metadata: {
          'path': path.toString(),
          'cache_path': cacheFilePath.toString(),
          'cache_stats': metadata.cacheStats,
          'operation': 'cache_write_success',
        },
      );
    } catch (e, stackTrace) {
      logger.warning(
        '缓存写入失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {'path': path.toString(), 'operation': 'cache_write_failed'},
      );
      // 静默处理缓存写入错误
    }
  }

  /// 删除缓存文件
  Future<void> deleteCache(Context context, Path path) async {
    final logger = context.logger;
    try {
      final cacheFilePath = _buildCacheMetadataFile(context, path);
      if (await cacheFileSystem.exists(context, cacheFilePath)) {
        await cacheFileSystem.delete(context, cacheFilePath);
        logger.trace(
          '缓存删除成功',
          metadata: {
            'path': path.toString(),
            'cache_path': cacheFilePath.toString(),
            'operation': 'cache_deleted',
          },
        );
      }
    } catch (e, stackTrace) {
      logger.warning(
        '缓存删除失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {'path': path.toString(), 'operation': 'cache_delete_failed'},
      );
      // 静默处理缓存删除错误
    }
  }
}

/// 缓存策略管理器，负责缓存有效性验证和失效策略
class _CacheStrategyManager {
  _CacheStrategyManager({
    required this.maxCacheAge,
    required this.storageManager,
  });

  final Duration maxCacheAge;
  final _CacheStorageManager storageManager;

  /// 验证缓存是否有效
  bool isCacheValid(MetadataCacheData cacheData, String expectedPath) {
    return cacheData.isValid(expectedPath: expectedPath, maxAge: maxCacheAge);
  }

  /// 获取有效的缓存数据
  Future<MetadataCacheData?> getValidCache(Context context, Path path) async {
    final logger = context.logger;
    final cachedData = await storageManager.readCache(context, path);

    if (cachedData == null) {
      return null;
    }

    if (!isCacheValid(cachedData, path.toString())) {
      logger.trace(
        '缓存已过期',
        metadata: {
          'path': path.toString(),
          'last_updated': cachedData.lastUpdated.toIso8601String(),
          'max_age_minutes': maxCacheAge.inMinutes,
          'operation': 'cache_expired',
        },
      );
      // 异步删除过期缓存
      unawaited(storageManager.deleteCache(context, path));
      return null;
    }

    logger.trace(
      '缓存命中',
      metadata: {
        'path': path.toString(),
        'cache_stats': cachedData.cacheStats,
        'last_updated': cachedData.lastUpdated.toIso8601String(),
        'operation': 'cache_hit',
      },
    );
    return cachedData;
  }

  /// 使缓存失效
  Future<void> invalidateCache(Context context, Path path) async {
    final logger = context.logger;
    await storageManager.deleteCache(context, path);
    logger.trace(
      '缓存失效成功',
      metadata: {'path': path.toString(), 'operation': 'cache_invalidated'},
    );
  }
}

/// 元数据缓存操作类
/// 负责协调各个组件，提供统一的API
class MetadataCacheOperation {
  MetadataCacheOperation({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    Duration maxCacheAge = const Duration(minutes: 30),
    this.largeDirectoryThreshold = 1000,
  }) {
    _storageManager = _CacheStorageManager(
      cacheFileSystem: cacheFileSystem,
      cacheDir: cacheDir,
    );
    _cacheStrategy = _CacheStrategyManager(
      maxCacheAge: maxCacheAge,
      storageManager: _storageManager,
    );
  }

  final IFileSystem originFileSystem;
  final int largeDirectoryThreshold;

  late final _CacheStorageManager _storageManager;
  late final _CacheStrategyManager _cacheStrategy;

  /// 刷新路径的元数据缓存
  Future<MetadataCacheData?> _refreshMetadataCache(
    Context context,
    Path path,
  ) async {
    final logger = context.logger;
    try {
      final status = await originFileSystem.stat(context, path);
      if (status == null) {
        await _cacheStrategy.invalidateCache(context, path);
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
                '目录子文件数量超过阈值，标记为大目录',
                metadata: {
                  'path': path.toString(),
                  'child_count': childCount,
                  'threshold': largeDirectoryThreshold,
                  'operation': 'mark_large_directory',
                },
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
            '目录列举失败',
            error: e,
            stackTrace: stackTrace,
            metadata: {
              'path': path.toString(),
              'operation': 'list_directory_failed',
            },
          );
          // 列举失败时不缓存子文件列表
        }
      }

      await _storageManager.writeCache(context, path, cacheData);
      return cacheData;
    } catch (e, stackTrace) {
      logger.warning(
        '缓存刷新失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'path': path.toString(),
          'operation': 'refresh_cache_failed',
        },
      );
      // 刷新失败时删除缓存
      await _cacheStrategy.invalidateCache(context, path);
      return null;
    }
  }

  /// 获取文件状态（优先从缓存）
  Future<FileStatus?> getFileStatus(Context context, Path path) async {
    final logger = context.logger;
    try {
      // 首先尝试从缓存读取
      final cachedData = await _cacheStrategy.getValidCache(context, path);
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
        '获取文件状态失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'path': path.toString(),
          'operation': 'get_file_status_failed',
        },
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
      final cachedData = await _cacheStrategy.getValidCache(context, path);
      if (cachedData != null && !cachedData.isLargeDirectory) {
        // 普通目录，从缓存读取子文件列表
        final children = cachedData.children;
        if (children != null) {
          logger.trace(
            '从缓存提供目录列表',
            metadata: {
              'path': path.toString(),
              'child_count': children.length,
              'cache_stats': cachedData.cacheStats,
              'operation': 'serve_from_cache',
            },
          );
          for (final child in children) {
            yield child;
          }
          return;
        }
      }

      // 缓存不存在、无效或是大目录，从原始文件系统获取
      logger.trace(
        '从原始文件系统提供目录列表',
        metadata: {
          'path': path.toString(),
          'reason': cachedData?.isLargeDirectory == true
              ? 'large_directory'
              : 'cache_miss',
          'operation': 'serve_from_origin',
        },
      );
      await for (final item in originFileSystem.list(context, path)) {
        yield item;
      }

      // 异步更新缓存
      unawaited(_refreshMetadataCache(context, path));
    } catch (e, stackTrace) {
      logger.warning(
        '目录列表获取失败',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'path': path.toString(),
          'operation': 'list_directory_failed',
        },
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
      await _cacheStrategy.invalidateCache(context, path);
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
