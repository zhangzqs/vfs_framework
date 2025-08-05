import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../abstract/index.dart';
import 'metadata.dart';

/// 缓存目录操作类，负责管理缓存文件系统的所有操作
class _CacheDirManager {
  _CacheDirManager({
    required this.cacheFileSystem,
    required this.cacheDir,
    required this.blockSize,
  });

  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final int blockSize;

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(Context context, Path path) {
    final logger = context.logger;
    // hash为长度为16的字符串
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.trace('生成路径哈希值', metadata: {'path': pathString, 'hash': hash});
    return hash;
  }

  /// 在cacheDir中，针对srcPath构建分层缓存目录路径，双层目录结构，有利于文件系统查询性能
  Path _buildCacheHashDir(Context context, Path path) {
    final logger = context.logger;
    final hash = _generatePathHash(context, path);
    // 使用前2位作为第一层目录 (每个level1下4096种可能)
    final level1 = hash.substring(0, 3);
    // 使用第4-6个字符作为第二层目录 (每个level2下4096种可能)
    final level2 = hash.substring(3, 6);
    // 第三级目录使用剩余的hash值
    final level3 = hash.substring(6);
    // 构建分层路径: cacheDir/abc/def/1234567890/
    final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

    logger.trace(
      '构建分层缓存路径',
      metadata: {
        'hash': hash,
        'level1': level1,
        'level2': level2,
        'level3': level3,
        'cache_path': hierarchicalPath.toString(),
        'original_path': path.toString(),
      },
    );
    return hierarchicalPath;
  }

  /// 检查缓存块是否存在
  Future<bool> blockExists(Context context, Path path, int blockIdx) async {
    final cacheHashDir = _buildCacheHashDir(context, path);
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());
    return await cacheFileSystem.exists(context, cacheBlockPath);
  }

  /// 从缓存文件系统读取完整块
  Future<Uint8List?> readBlock(Context context, Path path, int blockIdx) async {
    final logger = context.logger;
    final cacheHashDir = _buildCacheHashDir(context, path);
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());

    try {
      return await cacheFileSystem.readAsBytes(context, cacheBlockPath);
    } catch (e) {
      logger.warning(
        '读取缓存块失败',
        error: e,
        metadata: {'cache_path': cacheBlockPath.toString()},
      );
      return null; // 读取失败返回null
    }
  }

  /// 写入块数据到缓存
  Future<void> writeBlock(
    Context context,
    Path path,
    int blockIdx,
    Uint8List data,
  ) async {
    final logger = context.logger;
    final cacheHashDir = _buildCacheHashDir(context, path);
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());

    // 确保缓存目录结构存在
    await _ensureCacheDirectoryExists(context, cacheHashDir);
    await _ensureCacheDirectoryExists(context, cacheBlocksDir);

    // 写入块数据
    final sink = await cacheFileSystem.openWrite(
      context,
      cacheBlockPath,
      options: const WriteOptions(mode: WriteMode.overwrite),
    );

    sink.add(data);
    await sink.close();

    logger.trace(
      '缓存块写入成功',
      metadata: {
        'block_index': blockIdx,
        'data_size': data.length,
        'cache_path': cacheBlockPath.toString(),
      },
    );
  }

  /// 读取缓存元数据
  Future<CacheMetadata?> readMetadata(Context context, Path path) async {
    final logger = context.logger;
    final cacheHashDir = _buildCacheHashDir(context, path);
    final cacheMetaPath = cacheHashDir.join('meta.json');

    try {
      if (!await cacheFileSystem.exists(context, cacheMetaPath)) {
        return null;
      }

      final metaJson =
          json.decode(
                utf8.decode(
                  await cacheFileSystem.readAsBytes(context, cacheMetaPath),
                ),
              )
              as Map<String, dynamic>;
      return CacheMetadata.fromJson(metaJson);
    } catch (e) {
      logger.warning(
        '读取缓存元数据失败',
        error: e,
        metadata: {'meta_path': cacheMetaPath.toString()},
      );
      return null;
    }
  }

  /// 写入缓存元数据
  Future<void> _writeMetadata(
    Context context,
    Path path,
    CacheMetadata metadata,
  ) async {
    final logger = context.logger;
    final cacheHashDir = _buildCacheHashDir(context, path);
    final cacheMetaPath = cacheHashDir.join('meta.json');

    try {
      // 确保缓存目录存在
      await _ensureCacheDirectoryExists(context, cacheHashDir);

      // 写入元数据文件
      final metaJson = json.encode(metadata.toJson());
      final metaBytes = utf8.encode(metaJson);

      final sink = await cacheFileSystem.openWrite(
        context,
        cacheMetaPath,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      sink.add(metaBytes);
      await sink.close();

      logger.trace(
        '缓存元数据写入成功',
        metadata: {
          'meta_path': cacheMetaPath.toString(),
          'cache_stats': metadata.cacheStats,
        },
      );
    } catch (e) {
      logger.warning('写入缓存元数据失败', error: e);
    }
  }

  /// 删除整个path对应的缓存目录
  Future<void> delete(Context context, Path path) async {
    final logger = context.logger;
    final cacheHashDir = _buildCacheHashDir(context, path);

    try {
      if (await cacheFileSystem.exists(context, cacheHashDir)) {
        await cacheFileSystem.delete(
          context,
          cacheHashDir,
          options: const DeleteOptions(recursive: true),
        );
        logger.debug(
          '缓存目录删除成功',
          metadata: {'cache_dir': cacheHashDir.toString()},
        );

        // 尝试清理空的父级目录
        await _cleanupEmptyParentDirs(context, cacheHashDir);
      }
    } catch (e) {
      logger.warning(
        '删除缓存目录失败',
        error: e,
        metadata: {'cache_dir': cacheHashDir.toString()},
      );
    }
  }

  /// 列出缓存目录内容
  Future<List<FileStatus>> _listCacheDir(Context context, Path cacheDir) async {
    final items = <FileStatus>[];
    try {
      if (await cacheFileSystem.exists(context, cacheDir)) {
        await for (final item in cacheFileSystem.list(context, cacheDir)) {
          items.add(item);
        }
      }
    } catch (e) {
      // 静默处理列举错误
    }
    return items;
  }

  /// 确保缓存目录存在
  Future<void> _ensureCacheDirectoryExists(Context context, Path dir) async {
    if (!await cacheFileSystem.exists(context, dir)) {
      await cacheFileSystem.createDirectory(
        context,
        dir,
        options: const CreateDirectoryOptions(createParents: true),
      );
    }
  }

  /// 清理空的父级目录（避免留下大量空目录）
  Future<void> _cleanupEmptyParentDirs(
    Context context,
    Path cacheHashDir,
  ) async {
    final logger = context.logger;

    try {
      // 获取父级目录路径
      final level2Dir = cacheHashDir.parent; // xx/yy/ 目录
      final level1Dir = level2Dir?.parent; // xx/ 目录

      if (level2Dir != null &&
          await cacheFileSystem.exists(context, level2Dir)) {
        // 检查level2目录是否为空
        final level2Items = await _listCacheDir(context, level2Dir);

        if (level2Items.isEmpty) {
          await cacheFileSystem.delete(context, level2Dir);
          logger.trace(
            '清理空的二级目录',
            metadata: {'level2_dir': level2Dir.toString()},
          );

          // 检查level1目录是否也为空
          if (level1Dir != null &&
              await cacheFileSystem.exists(context, level1Dir)) {
            final level1Items = await _listCacheDir(context, level1Dir);

            if (level1Items.isEmpty) {
              await cacheFileSystem.delete(context, level1Dir);
              logger.trace(
                '清理空的一级目录',
                metadata: {'level1_dir': level1Dir.toString()},
              );
            }
          }
        }
      }
    } catch (e) {
      // 静默处理清理错误，不影响主要功能
      logger.trace('清理空的父级目录失败', error: e);
    }
  }
}

/// 内存缓存管理器，负责管理文件状态、元数据等内存缓存
class _MemoryCacheManager {
  // 性能优化缓存
  final Map<String, FileStatus> _fileStatCache = {}; // 文件状态缓存
  final Map<String, CacheMetadata> _metadataCache = {}; // 元数据缓存
  final Map<String, bool> _integrityCache = {}; // 完整性验证缓存
  final Map<String, DateTime> _cacheTimestamps = {}; // 缓存时间戳

  static const Duration _cacheValidDuration = Duration(seconds: 30); // 缓存有效期

  /// 检查缓存是否有效（避免重复检查）
  bool isCacheValid(String pathString) {
    final timestamp = _cacheTimestamps[pathString];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheValidDuration;
  }

  /// 获取缓存的文件状态信息
  Future<FileStatus?> getFileStatWithCache(
    Context context,
    Path path,
    IFileSystem originFileSystem,
  ) async {
    final pathString = path.toString();

    // 检查缓存是否有效
    if (isCacheValid(pathString) && _fileStatCache.containsKey(pathString)) {
      return _fileStatCache[pathString];
    }

    // 缓存无效或不存在，重新获取
    final stat = await originFileSystem.stat(context, path);
    if (stat != null) {
      _fileStatCache[pathString] = stat;
      _cacheTimestamps[pathString] = DateTime.now();
    }
    return stat;
  }

  /// 获取缓存的元数据
  CacheMetadata? getCachedMetadata(String pathString) {
    if (isCacheValid(pathString) && _metadataCache.containsKey(pathString)) {
      return _metadataCache[pathString];
    }
    return null;
  }

  /// 缓存元数据
  void cacheMetadata(String pathString, CacheMetadata metadata) {
    _metadataCache[pathString] = metadata;
    _cacheTimestamps[pathString] = DateTime.now();
  }

  /// 获取缓存的完整性验证结果
  bool? getCachedIntegrityResult(String pathString) {
    if (isCacheValid(pathString) && _integrityCache.containsKey(pathString)) {
      return _integrityCache[pathString];
    }
    return null;
  }

  /// 缓存完整性验证结果
  void cacheIntegrityResult(String pathString, bool result) {
    _integrityCache[pathString] = result;
    _cacheTimestamps[pathString] = DateTime.now();
  }

  /// 清理指定文件的内存缓存
  void clearMemoryCache(String pathString) {
    _fileStatCache.remove(pathString);
    _metadataCache.remove(pathString);
    _integrityCache.remove(pathString);
    _cacheTimestamps.remove(pathString);
  }

  /// 清理所有过期的内存缓存
  void cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheValidDuration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      clearMemoryCache(key);
    }
  }
}

/// 预读管理器，负责管理预读策略和任务
class _ReadAheadManager {
  _ReadAheadManager({
    required this.readAheadBlocks,
    required this.enableReadAhead,
    required this.blockSize,
  });

  final int readAheadBlocks;
  final bool enableReadAhead;
  final int blockSize;

  // 预读队列管理
  final Map<String, Set<int>> _activeReadAheadTasks = {}; // 记录正在进行的预读任务
  final Map<String, int> _lastAccessedBlock = {}; // 记录每个文件最后访问的块索引

  /// 触发预读操作
  void triggerReadAhead(Context context, Path path, int currentBlockIdx) {
    if (!enableReadAhead || readAheadBlocks <= 0) return;

    final logger = context.logger;
    final pathString = path.toString();

    // 更新最后访问的块索引
    final lastBlock = _lastAccessedBlock[pathString];
    _lastAccessedBlock[pathString] = currentBlockIdx;

    // 检查是否是顺序访问（预读只对顺序访问有效）
    final isSequentialAccess =
        lastBlock == null ||
        currentBlockIdx == lastBlock + 1 ||
        currentBlockIdx == lastBlock; // 允许重复访问同一块

    if (!isSequentialAccess) {
      logger.trace(
        '检测到非顺序访问，跳过预读',
        metadata: {
          'path': path.toString(),
          'last_block': lastBlock,
          'current_block': currentBlockIdx,
        },
      );
      return;
    }

    logger.trace(
      '触发预读操作',
      metadata: {
        'path': path.toString(),
        'current_block': currentBlockIdx,
        'last_block': lastBlock,
      },
    );
  }

  /// 执行预读操作
  void performReadAhead(
    Context context,
    Path path,
    int currentBlockIdx,
    _MemoryCacheManager memoryCache,
    _CacheDirManager cacheDirOp,
    _CacheStrategyManager cacheStrategy,
    IFileSystem originFileSystem,
    Future<Uint8List> Function(Context, Path, int) readBlockFromOrigin,
  ) {
    final logger = context.logger;

    Future.microtask(() async {
      final pathString = path.toString();

      try {
        // 获取文件大小来确定有效的块范围（使用缓存）
        final fileStatus = await memoryCache.getFileStatWithCache(
          context,
          path,
          originFileSystem,
        );
        if (fileStatus == null) {
          return;
        }

        final fileSize = fileStatus.size ?? 0;
        final maxBlockIdx = (fileSize + blockSize - 1) ~/ blockSize - 1;

        // 定期清理过期缓存
        memoryCache.cleanupExpiredCache();

        // 初始化活跃任务集合
        _activeReadAheadTasks[pathString] ??= <int>{};
        final activeTasks = _activeReadAheadTasks[pathString]!;

        // 预读后续的块
        final readAheadTasks = <Future<void>>[];

        for (int i = 1; i <= readAheadBlocks; i++) {
          final targetBlockIdx = currentBlockIdx + i;

          // 检查块索引是否有效
          if (targetBlockIdx > maxBlockIdx) {
            break;
          }

          // 检查是否已经在预读队列中
          if (activeTasks.contains(targetBlockIdx)) {
            continue;
          }

          // 检查缓存是否已存在
          if (await cacheDirOp.blockExists(context, path, targetBlockIdx)) {
            continue;
          }

          // 添加到活跃任务并开始预读
          activeTasks.add(targetBlockIdx);

          readAheadTasks.add(
            _readAheadBlock(
              context,
              path,
              targetBlockIdx,
              cacheDirOp,
              cacheStrategy,
              originFileSystem,
              readBlockFromOrigin,
            ),
          );
        }

        // 等待所有预读任务完成（但不阻塞主流程）
        if (readAheadTasks.isNotEmpty) {
          logger.trace(
            '开始预读任务',
            metadata: {
              'path': path.toString(),
              'task_count': readAheadTasks.length,
              'after_block': currentBlockIdx,
            },
          );

          await Future.wait(readAheadTasks);

          logger.trace(
            '预读任务完成',
            metadata: {
              'path': path.toString(),
              'completed_tasks': readAheadTasks.length,
            },
          );
        }
      } catch (e) {
        logger.warning(
          '预读失败',
          error: e,
          metadata: {'path': path.toString(), 'current_block': currentBlockIdx},
        );
      }
    });
  }

  /// 预读单个块
  Future<void> _readAheadBlock(
    Context context,
    Path path,
    int blockIdx,
    _CacheDirManager cacheDirOp,
    _CacheStrategyManager cacheStrategy,
    IFileSystem originFileSystem,
    Future<Uint8List> Function(Context, Path, int) readBlockFromOrigin,
  ) async {
    final logger = context.logger;
    final pathString = path.toString();

    try {
      logger.trace(
        '预读：开始获取块',
        metadata: {'path': path.toString(), 'block_index': blockIdx},
      );

      // 从原始文件系统读取块数据
      final blockData = await readBlockFromOrigin(context, path, blockIdx);

      // 写入块数据到缓存
      await cacheDirOp.writeBlock(context, path, blockIdx, blockData);

      // 更新元数据
      await cacheStrategy.updateCacheMetadata(
        context,
        path,
        blockIdx,
        originFileSystem,
      );

      logger.trace(
        '预读：成功缓存块',
        metadata: {
          'path': path.toString(),
          'block_index': blockIdx,
          'data_size': blockData.length,
        },
      );
    } catch (e) {
      logger.warning(
        '预读：缓存块失败',
        error: e,
        metadata: {'path': path.toString(), 'block_index': blockIdx},
      );
    } finally {
      // 从活跃任务集合中移除
      _activeReadAheadTasks[pathString]?.remove(blockIdx);

      // 如果没有活跃任务了，清理集合
      if (_activeReadAheadTasks[pathString]?.isEmpty == true) {
        _activeReadAheadTasks.remove(pathString);
      }
    }
  }

  /// 清理预读状态（当文件缓存失效时调用）
  void cleanupReadAheadState(Context context, Path path) {
    final logger = context.logger;
    final pathString = path.toString();
    _activeReadAheadTasks.remove(pathString);
    _lastAccessedBlock.remove(pathString);

    logger.trace('清理预读状态', metadata: {'path': path.toString()});
  }
}

/// 缓存策略管理器，负责缓存验证和失效策略
class _CacheStrategyManager {
  _CacheStrategyManager({
    required this.blockSize,
    required this.memoryCache,
    required this.cacheDirOp,
  });

  final int blockSize;
  final _MemoryCacheManager memoryCache;
  final _CacheDirManager cacheDirOp;

  /// 验证缓存完整性（带缓存优化）- 避免重复验证
  Future<bool> validateCacheIntegrityWithCache(
    Context context,
    Path path,
    IFileSystem originFileSystem,
  ) async {
    final logger = context.logger;
    final pathString = path.toString();

    // 检查是否已经验证过且仍然有效
    final cachedResult = memoryCache.getCachedIntegrityResult(pathString);
    if (cachedResult != null) {
      logger.trace(
        '使用缓存的完整性验证结果',
        metadata: {'path': pathString, 'cached_result': cachedResult},
      );
      return cachedResult;
    }

    try {
      // 读取缓存的元数据
      CacheMetadata? metadata = memoryCache.getCachedMetadata(pathString);
      if (metadata == null) {
        metadata = await cacheDirOp.readMetadata(context, path);
        if (metadata != null) {
          memoryCache.cacheMetadata(pathString, metadata);
        }
      }

      if (metadata == null) {
        logger.trace('未找到缓存元数据文件', metadata: {'original_path': pathString});
        memoryCache.cacheIntegrityResult(pathString, false);
        return false;
      }

      // 获取原文件的状态信息（使用缓存）
      final originalStat = await memoryCache.getFileStatWithCache(
        context,
        path,
        originFileSystem,
      );
      if (originalStat == null) {
        logger.warning('原文件不存在', metadata: {'original_path': pathString});
        memoryCache.cacheIntegrityResult(pathString, false);
        return false;
      }

      // 使用CacheMetadata的isValid方法进行验证
      final isValid = metadata.isValid(
        expectedPath: pathString,
        expectedFileSize: originalStat.size ?? 0,
        expectedBlockSize: blockSize,
      );

      // 缓存验证结果
      memoryCache.cacheIntegrityResult(pathString, isValid);

      if (!isValid) {
        logger.warning(
          '缓存元数据验证失败',
          metadata: {
            'path': pathString,
            'cache_metadata': metadata.toJson(),
            'expected_file_size': originalStat.size ?? 0,
            'expected_block_size': blockSize,
          },
        );
        return false;
      }

      logger.trace(
        '缓存验证通过',
        metadata: {'path': pathString, 'cache_stats': metadata.cacheStats},
      );
      return true;
    } catch (e) {
      logger.warning('缓存完整性验证失败', error: e);
      memoryCache.cacheIntegrityResult(pathString, false);
      return false;
    }
  }

  /// 更新缓存元数据（批量优化版本）
  Future<void> updateCacheMetadata(
    Context context,
    Path path,
    int blockIdx,
    IFileSystem originFileSystem,
  ) async {
    final logger = context.logger;
    final pathString = path.toString();

    try {
      // 获取原文件信息（使用缓存）
      final originalStat = await memoryCache.getFileStatWithCache(
        context,
        path,
        originFileSystem,
      );
      if (originalStat == null) {
        logger.warning(
          '无法获取原文件状态信息用于元数据更新',
          metadata: {'original_path': pathString},
        );
        return;
      }

      final fileSize = originalStat.size ?? 0;
      final totalBlocks = (fileSize + blockSize - 1) ~/ blockSize; // 向上取整

      CacheMetadata metadata;

      // 优先使用内存中的元数据缓存
      final cachedMetadata = memoryCache.getCachedMetadata(pathString);
      if (cachedMetadata != null) {
        metadata = cachedMetadata.addCachedBlock(blockIdx);
      } else {
        // 如果缓存中没有，再从磁盘读取
        final existingMetadata = await cacheDirOp.readMetadata(context, path);
        if (existingMetadata != null) {
          metadata = existingMetadata.addCachedBlock(blockIdx);
        } else {
          // 创建新的元数据
          metadata = CacheMetadata(
            filePath: pathString,
            fileSize: fileSize,
            blockSize: blockSize,
            totalBlocks: totalBlocks,
            cachedBlocks: {blockIdx},
            lastModified: DateTime.now(),
          );
        }
      }

      // 更新内存缓存
      memoryCache.cacheMetadata(pathString, metadata);

      // 写入元数据文件
      await cacheDirOp._writeMetadata(context, path, metadata);

      logger.trace(
        '缓存元数据更新成功',
        metadata: {
          'path': pathString,
          'block_index': blockIdx,
          'cache_stats': metadata.cacheStats,
          'total_blocks': totalBlocks,
          'file_size': fileSize,
        },
      );
    } catch (e) {
      logger.warning('更新缓存元数据失败', error: e);
      // 元数据更新失败不影响缓存数据本身
    }
  }
}

class CacheManager {
  CacheManager({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    required this.blockSize,
    int readAheadBlocks = 2, // 默认预读2个块
    bool enableReadAhead = true, // 默认启用预读
  }) : _cacheDirManager = _CacheDirManager(
         cacheFileSystem: cacheFileSystem,
         cacheDir: cacheDir,
         blockSize: blockSize,
       ),
       _memoryCacheManager = _MemoryCacheManager(),
       _readAheadManager = _ReadAheadManager(
         readAheadBlocks: readAheadBlocks,
         enableReadAhead: enableReadAhead,
         blockSize: blockSize,
       ) {
    _cacheStrategyManager = _CacheStrategyManager(
      blockSize: blockSize,
      memoryCache: _memoryCacheManager,
      cacheDirOp: _cacheDirManager,
    );
  }

  final IFileSystem originFileSystem;
  final int blockSize;
  final _CacheDirManager _cacheDirManager;
  final _MemoryCacheManager _memoryCacheManager;
  final _ReadAheadManager _readAheadManager;
  late final _CacheStrategyManager _cacheStrategyManager;

  /// 实现块缓存的读取
  Stream<List<int>> openReadWithBlockCache(
    Context context,
    Path path,
    ReadOptions options,
  ) async* {
    final logger = context.logger;

    logger.trace(
      '开始块缓存读取',
      metadata: {
        'path': path.toString(),
        'read_options': {'start': options.start, 'end': options.end},
      },
    );

    // 获取文件状态信息
    final fileStatus = await originFileSystem.stat(context, path);
    if (fileStatus == null) {
      throw FileSystemException.notFound(path);
    }
    if (fileStatus.isDirectory) {
      throw FileSystemException.notAFile(path);
    }
    final fileSize = fileStatus.size ?? 0;
    if (fileSize == 0) {
      logger.trace(
        '文件为空，直接返回',
        metadata: {'path': path.toString(), 'file_size': fileSize},
      );
      return; // 空文件直接返回
    }
    // 计算读取范围
    final startOffset = options.start ?? 0;
    final endOffset = options.end ?? fileSize;
    final readLength = endOffset - startOffset;

    if (readLength <= 0) {
      logger.warning(
        '无效的读取范围',
        metadata: {
          'path': path.toString(),
          'start_offset': startOffset,
          'end_offset': endOffset,
          'read_length': readLength,
        },
      );
      return; // 无效的读取范围
    }

    // 计算涉及的块范围
    final startBlockIdx = startOffset ~/ blockSize;
    // 确保endOffset不会导致负数计算
    final endBlockIdx = max(0, (endOffset - 1) ~/ blockSize);
    final totalBlocks = endBlockIdx - startBlockIdx + 1;

    logger.trace(
      '计算读取块范围',
      metadata: {
        'path': path.toString(),
        'start_block': startBlockIdx,
        'end_block': endBlockIdx,
        'total_blocks': totalBlocks,
        'file_size': fileSize,
        'block_size': blockSize,
      },
    );

    // 逐块读取数据
    var currentOffset = startOffset;
    var remainingBytes = readLength;

    for (var blockIdx = startBlockIdx; blockIdx <= endBlockIdx; blockIdx++) {
      if (remainingBytes <= 0) break;

      // 获取当前块的数据
      final blockData = await _getBlockData(context, blockIdx, path);

      // 计算当前块内的偏移量和读取长度
      final blockStartOffset = blockIdx * blockSize;
      final offsetInBlock = max(0, currentOffset - blockStartOffset);
      final bytesToRead = min(blockSize - offsetInBlock, remainingBytes);

      // 确保不会超出实际块数据的范围（防止文件末尾块的越界问题）
      final actualBytesToRead = min(
        bytesToRead,
        blockData.length - offsetInBlock,
      );
      final endIndex = offsetInBlock + actualBytesToRead;

      // 提取需要的部分数据
      final dataToYield = blockData.sublist(offsetInBlock, endIndex);

      yield dataToYield;

      currentOffset += actualBytesToRead;
      remainingBytes -= actualBytesToRead;
    }

    logger.trace(
      '完成块缓存读取',
      metadata: {
        'path': path.toString(),
        'total_blocks_read': totalBlocks,
        'total_bytes_read': readLength - remainingBytes,
      },
    );
  }

  /// 获取指定块的数据（带缓存和预读）- 性能优化版本
  Future<Uint8List> _getBlockData(
    Context context,
    int blockIdx,
    Path path,
  ) async {
    final logger = context.logger;

    try {
      // 首先检查缓存是否存在
      if (await _cacheDirManager.blockExists(context, path, blockIdx)) {
        // 使用缓存的完整性验证结果，避免重复验证
        if (await _cacheStrategyManager.validateCacheIntegrityWithCache(
          context,
          path,
          originFileSystem,
        )) {
          final cachedData = await _cacheDirManager.readBlock(
            context,
            path,
            blockIdx,
          );
          if (cachedData != null) {
            logger.trace(
              '缓存命中',
              metadata: {
                'path': path.toString(),
                'block_index': blockIdx,
                'block_size': cachedData.length,
              },
            );

            // 触发预读
            _triggerReadAhead(context, path, blockIdx);

            return cachedData;
          }
        } else {
          logger.warning(
            '缓存完整性检查失败，可能存在哈希冲突，使缓存失效',
            metadata: {'path': path.toString(), 'block_index': blockIdx},
          );
          await invalidateCache(context, path);
        }
      }

      // 缓存不存在或验证失败，从原始文件系统读取
      logger.trace(
        '缓存未命中，从原始文件系统读取',
        metadata: {'path': path.toString(), 'block_index': blockIdx},
      );
      final blockData = await _readBlockFromOrigin(context, path, blockIdx);

      // 异步写入缓存（不阻塞读取）
      _writeToCacheAsync(context, path, blockIdx, blockData);

      // 触发预读
      _triggerReadAhead(context, path, blockIdx);

      return blockData;
    } catch (e) {
      logger.warning(
        '读取块缓存时发生错误，回退到原始文件系统',
        error: e,
        metadata: {'path': path.toString(), 'block_index': blockIdx},
      );
      // 缓存读取失败，回退到原始文件系统
      final blockData = await _readBlockFromOrigin(context, path, blockIdx);

      // 即使出错也尝试触发预读
      _triggerReadAhead(context, path, blockIdx);

      return blockData;
    }
  }

  /// 触发预读操作的包装方法
  void _triggerReadAhead(Context context, Path path, int currentBlockIdx) {
    _readAheadManager.triggerReadAhead(context, path, currentBlockIdx);

    // 实际执行预读
    _readAheadManager.performReadAhead(
      context,
      path,
      currentBlockIdx,
      _memoryCacheManager,
      _cacheDirManager,
      _cacheStrategyManager,
      originFileSystem,
      _readBlockFromOrigin,
    );
  }

  /// 从原始文件系统读取指定块（优化版本）
  Future<Uint8List> _readBlockFromOrigin(
    Context context,
    Path path,
    int blockIdx,
  ) async {
    final logger = context.logger;

    final blockStart = blockIdx * blockSize;

    // 获取文件大小以确保不会读取超出文件末尾的数据（使用缓存）
    final fileStatus = await _memoryCacheManager.getFileStatWithCache(
      context,
      path,
      originFileSystem,
    );
    final fileSize = fileStatus?.size ?? 0;

    // 如果块的起始位置已经超出文件大小，返回空数据
    if (blockStart >= fileSize) {
      logger.trace(
        '块起始位置超出文件大小',
        metadata: {
          'path': path.toString(),
          'block_index': blockIdx,
          'block_start': blockStart,
          'file_size': fileSize,
        },
      );
      return Uint8List(0);
    }

    // 计算实际的读取结束位置，不超过文件大小
    final blockEnd = min(blockStart + blockSize, fileSize);

    final readOptions = ReadOptions(start: blockStart, end: blockEnd);

    logger.trace(
      '从原始文件系统读取块',
      metadata: {
        'path': path.toString(),
        'block_index': blockIdx,
        'block_start': blockStart,
        'block_end': blockEnd,
        'file_size': fileSize,
      },
    );
    return originFileSystem.readAsBytes(context, path, options: readOptions);
  }

  /// 异步写入缓存（不阻塞主流程）
  void _writeToCacheAsync(
    Context context,
    Path path,
    int blockIdx,
    Uint8List data,
  ) {
    final logger = context.logger;

    // 使用Future.microtask确保不阻塞当前操作
    Future.microtask(() async {
      try {
        // 写入块数据
        await _cacheDirManager.writeBlock(context, path, blockIdx, data);

        // 更新或创建meta.json文件
        await _cacheStrategyManager.updateCacheMetadata(
          context,
          path,
          blockIdx,
          originFileSystem,
        );

        logger.trace(
          '缓存写入成功',
          metadata: {
            'path': path.toString(),
            'block_index': blockIdx,
            'data_size': data.length,
          },
        );
      } catch (e) {
        logger.warning(
          '缓存写入失败',
          error: e,
          metadata: {'path': path.toString(), 'block_index': blockIdx},
        );
        // 静默处理缓存写入错误，不影响主流程
      }
    });
  }

  /// 使指定文件的缓存失效
  Future<void> invalidateCache(Context context, Path path) async {
    final logger = context.logger;
    final pathString = path.toString();

    try {
      logger.debug('使缓存失效', metadata: {'path': pathString});

      // 清理预读状态
      _readAheadManager.cleanupReadAheadState(context, path);

      // 清理内存缓存
      _memoryCacheManager.clearMemoryCache(pathString);

      // 删除缓存目录
      await _cacheDirManager.delete(context, path);

      logger.debug('缓存失效成功', metadata: {'path': pathString});
    } catch (e) {
      logger.warning('缓存失效失败', error: e, metadata: {'path': pathString});
      // 静默处理缓存清理错误，不影响主流程
    }
  }
}
