import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../abstract/index.dart';
import 'metadata.dart';

/// 缓存目录操作类，负责管理缓存文件系统的所有操作
class _CacheDirOperation {
  _CacheDirOperation({
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

class CacheOperation {
  CacheOperation({
    required this.originFileSystem,
    required IFileSystem cacheFileSystem,
    required Path cacheDir,
    required this.blockSize,
    this.readAheadBlocks = 2, // 默认预读2个块
    this.enableReadAhead = true, // 默认启用预读
  }) : _cacheDirOp = _CacheDirOperation(
         cacheFileSystem: cacheFileSystem,
         cacheDir: cacheDir,
         blockSize: blockSize,
       );

  final IFileSystem originFileSystem;
  final int blockSize;
  final int readAheadBlocks;
  final bool enableReadAhead;
  final _CacheDirOperation _cacheDirOp;

  // 预读队列管理
  final Map<String, Set<int>> _activeReadAheadTasks = {}; // 记录正在进行的预读任务
  final Map<String, int> _lastAccessedBlock = {}; // 记录每个文件最后访问的块索引

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

  /// 获取指定块的数据（带缓存和预读）
  Future<Uint8List> _getBlockData(
    Context context,
    int blockIdx,
    Path path,
  ) async {
    final logger = context.logger;

    try {
      // 首先检查缓存是否存在
      if (await _cacheDirOp.blockExists(context, path, blockIdx)) {
        // 验证缓存完整性和hash冲突
        if (await _validateCacheIntegrity(context, path)) {
          final cachedData = await _cacheDirOp.readBlock(
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

  /// 从原始文件系统读取指定块
  Future<Uint8List> _readBlockFromOrigin(
    Context context,
    Path path,
    int blockIdx,
  ) async {
    final logger = context.logger;

    final blockStart = blockIdx * blockSize;

    // 获取文件大小以确保不会读取超出文件末尾的数据
    final fileStatus = await originFileSystem.stat(context, path);
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
        await _cacheDirOp.writeBlock(context, path, blockIdx, data);

        // 更新或创建meta.json文件
        await _updateCacheMetadata(context, path, blockIdx);

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

  /// 验证缓存完整性，防止hash冲突
  Future<bool> _validateCacheIntegrity(Context context, Path path) async {
    final logger = context.logger;

    try {
      final metadata = await _cacheDirOp.readMetadata(context, path);
      if (metadata == null) {
        logger.trace(
          '未找到缓存元数据文件',
          metadata: {'original_path': path.toString()},
        );
        return false;
      }

      // 获取原文件的状态信息进行验证
      final originalStat = await originFileSystem.stat(context, path);
      if (originalStat == null) {
        logger.warning('原文件不存在', metadata: {'original_path': path.toString()});
        return false; // 原文件不存在
      }

      // 使用CacheMetadata的isValid方法进行验证
      final isValid = metadata.isValid(
        expectedPath: path.toString(),
        expectedFileSize: originalStat.size ?? 0,
        expectedBlockSize: blockSize,
      );

      if (!isValid) {
        logger.warning(
          '缓存元数据验证失败',
          metadata: {
            'path': path.toString(),
            'cache_metadata': metadata.toJson(),
            'expected_file_size': originalStat.size ?? 0,
            'expected_block_size': blockSize,
          },
        );
        return false;
      }

      logger.trace(
        '缓存验证通过',
        metadata: {'path': path.toString(), 'cache_stats': metadata.cacheStats},
      );
      return true;
    } catch (e) {
      logger.warning('缓存完整性验证失败', error: e);
      return false;
    }
  }

  /// 更新缓存元数据
  Future<void> _updateCacheMetadata(
    Context context,
    Path path,
    int blockIdx,
  ) async {
    final logger = context.logger;

    try {
      // 获取原文件信息
      final originalStat = await originFileSystem.stat(context, path);
      if (originalStat == null) {
        logger.warning(
          '无法获取原文件状态信息用于元数据更新',
          metadata: {'original_path': path.toString()},
        );
        return;
      }

      final fileSize = originalStat.size ?? 0;
      final totalBlocks = (fileSize + blockSize - 1) ~/ blockSize; // 向上取整

      CacheMetadata metadata;

      // 如果元数据文件已存在，先读取现有数据
      final existingMetadata = await _cacheDirOp.readMetadata(context, path);
      if (existingMetadata != null) {
        metadata = existingMetadata.addCachedBlock(blockIdx);
      } else {
        // 创建新的元数据
        metadata = CacheMetadata(
          filePath: path.toString(),
          fileSize: fileSize,
          blockSize: blockSize,
          totalBlocks: totalBlocks,
          cachedBlocks: {blockIdx},
          lastModified: DateTime.now(),
        );
      }

      // 写入元数据文件
      await _cacheDirOp._writeMetadata(context, path, metadata);

      logger.trace(
        '缓存元数据更新成功',
        metadata: {
          'path': path.toString(),
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

  /// 使指定文件的缓存失效
  Future<void> invalidateCache(Context context, Path path) async {
    final logger = context.logger;

    try {
      logger.debug('使缓存失效', metadata: {'path': path.toString()});

      // 清理预读状态
      _cleanupReadAheadState(context, path);

      // 删除缓存目录
      await _cacheDirOp.delete(context, path);

      logger.debug('缓存失效成功', metadata: {'path': path.toString()});
    } catch (e) {
      logger.warning('缓存失效失败', error: e, metadata: {'path': path.toString()});
      // 静默处理缓存清理错误，不影响主流程
    }
  }

  /// 触发预读操作
  void _triggerReadAhead(Context context, Path path, int currentBlockIdx) {
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
    // 异步执行预读
    _performReadAhead(context, path, currentBlockIdx);
  }

  /// 执行预读操作
  void _performReadAhead(Context context, Path path, int currentBlockIdx) {
    final logger = context.logger;

    Future.microtask(() async {
      final pathString = path.toString();

      try {
        // 获取文件大小来确定有效的块范围
        final fileStatus = await originFileSystem.stat(context, path);
        if (fileStatus == null) {
          return;
        }

        final fileSize = fileStatus.size ?? 0;
        final maxBlockIdx = (fileSize + blockSize - 1) ~/ blockSize - 1;

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
          if (await _cacheDirOp.blockExists(context, path, targetBlockIdx)) {
            continue;
          }

          // 添加到活跃任务并开始预读
          activeTasks.add(targetBlockIdx);

          readAheadTasks.add(_readAheadBlock(context, path, targetBlockIdx));
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
  Future<void> _readAheadBlock(Context context, Path path, int blockIdx) async {
    final logger = context.logger;
    final pathString = path.toString();

    try {
      logger.trace(
        '预读：开始获取块',
        metadata: {'path': path.toString(), 'block_index': blockIdx},
      );

      // 从原始文件系统读取块数据
      final blockData = await _readBlockFromOrigin(context, path, blockIdx);

      // 写入块数据到缓存
      await _cacheDirOp.writeBlock(context, path, blockIdx, blockData);

      // 更新元数据
      await _updateCacheMetadata(context, path, blockIdx);

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
  void _cleanupReadAheadState(Context context, Path path) {
    final logger = context.logger;
    final pathString = path.toString();
    _activeReadAheadTasks.remove(pathString);
    _lastAccessedBlock.remove(pathString);

    logger.trace('清理预读状态', metadata: {'path': path.toString()});
  }
}
