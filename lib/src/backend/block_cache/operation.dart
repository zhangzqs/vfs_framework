import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../abstract/index.dart';
import 'metadata.dart';

class CacheOperation {
  CacheOperation({
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    required this.blockSize,
    this.readAheadBlocks = 2, // 默认预读2个块
    this.enableReadAhead = true, // 默认启用预读
  });
  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final int blockSize;
  final int readAheadBlocks;
  final bool enableReadAhead;

  // 预读队列管理
  final Map<String, Set<int>> _activeReadAheadTasks = {}; // 记录正在进行的预读任务
  final Map<String, int> _lastAccessedBlock = {}; // 记录每个文件最后访问的块索引

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(FileSystemContext context, Path path) {
    final logger = context.logger;
    // hash为长度为16的字符串
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.trace('Generated hash for ${path.toString()}: $hash');
    return hash;
  }

  /// 在cacheDir中，针对srcPath构建分层缓存目录路径，双层目录结构，有利于文件系统查询性能
  Path _buildCacheHashDir(FileSystemContext context, Path path) {
    final logger = context.logger;
    final hash = _generatePathHash(context, path);
    // 使用前2位作为第一层目录 (每个level1下4096种可能)
    final level1 = hash.substring(0, 3);
    // 使用第3-4位作为第二层目录 (每个level2下4096种可能)
    final level2 = hash.substring(3, 6);
    // 第三级目录使用剩余的hash值
    final level3 = hash.substring(6);
    // 构建分层路径: cacheDir/abc/def/1234ef567890/
    final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

    logger.trace(
      'Built hierarchical cache path for hash $hash: '
      '${hierarchicalPath.toString()}',
    );
    return hierarchicalPath;
  }

  /// 实现块缓存的读取
  Stream<List<int>> openReadWithBlockCache(
    FileSystemContext context,
    Path path,
    ReadOptions options,
  ) async* {
    final logger = context.logger;

    logger.trace('Starting block-cached read for ${path.toString()}');

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
      logger.trace('File is empty: ${path.toString()}');
      return; // 空文件直接返回
    }
    // 计算读取范围
    final startOffset = options.start ?? 0;
    final endOffset = options.end ?? fileSize;
    final readLength = endOffset - startOffset;

    if (readLength <= 0) {
      logger.warning(
        'Invalid read range for ${path.toString()}: '
        'start=$startOffset, end=$endOffset',
      );
      return; // 无效的读取范围
    }
    // 计算涉及的块范围
    final startBlockIdx = startOffset ~/ blockSize;
    final endBlockIdx = (endOffset - 1) ~/ blockSize;
    final totalBlocks = endBlockIdx - startBlockIdx + 1;

    logger.trace(
      'Reading ${path.toString()}: blocks $startBlockIdx-$endBlockIdx '
      '($totalBlocks blocks)',
    );

    // 生成文件路径的hash
    final cacheHashDir = _buildCacheHashDir(context, path);

    // 逐块读取数据
    var currentOffset = startOffset;
    var remainingBytes = readLength;

    for (var blockIdx = startBlockIdx; blockIdx <= endBlockIdx; blockIdx++) {
      if (remainingBytes <= 0) break;

      // 获取当前块的数据
      final blockData = await _getBlockData(
        context,
        cacheHashDir,
        blockIdx,
        path,
      );

      // 计算当前块内的偏移量和读取长度
      final blockStartOffset = blockIdx * blockSize;
      final offsetInBlock = max(0, currentOffset - blockStartOffset);
      final bytesToRead = min(blockSize - offsetInBlock, remainingBytes);

      // 提取需要的部分数据
      final dataToYield = blockData.sublist(
        offsetInBlock,
        offsetInBlock + bytesToRead,
      );

      yield dataToYield;

      currentOffset += bytesToRead;
      remainingBytes -= bytesToRead;
    }

    logger.trace('Completed block-cached read for ${path.toString()}');
  }

  /// 获取指定块的数据（带缓存和预读）
  Future<Uint8List> _getBlockData(
    FileSystemContext context,
    Path cacheHashDir,
    int blockIdx,
    Path originalPath,
  ) async {
    final logger = context.logger;

    // 构建分层缓存路径：<cacheHashDir>/blocks/<blockIdx> 和 <cacheHashDir>/meta.json
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());
    final cacheMetaPath = cacheHashDir.join('meta.json');

    try {
      // 首先检查缓存是否存在
      if (await cacheFileSystem.exists(context, cacheBlockPath)) {
        // 验证缓存完整性和hash冲突
        if (await _validateCacheIntegrity(
          context,
          cacheMetaPath,
          originalPath,
        )) {
          final cachedData = await _readFullBlock(
            context,
            cacheFileSystem,
            cacheBlockPath,
          );
          if (cachedData != null) {
            logger.trace(
              'Cache hit for ${originalPath.toString()}, block $blockIdx',
            );

            // 触发预读
            _triggerReadAhead(context, originalPath, blockIdx);

            return cachedData;
          }
        } else {
          logger.warning(
            'Cache integrity check failed for ${originalPath.toString()}, '
            'possible hash collision detected, invalidating cache',
          );
          await invalidateCache(context, originalPath);
        }
      }

      // 缓存不存在或验证失败，从原始文件系统读取
      logger.trace(
        'Cache miss for ${originalPath.toString()}, block $blockIdx, '
        'reading from origin',
      );
      final blockData = await _readBlockFromOrigin(
        context,
        originalPath,
        blockIdx,
      );

      // 异步写入缓存（不阻塞读取）
      _writeToCacheAsync(
        context,
        cacheHashDir,
        cacheBlocksDir,
        cacheBlockPath,
        cacheMetaPath,
        originalPath,
        blockIdx,
        blockData,
      );

      // 触发预读
      _triggerReadAhead(context, originalPath, blockIdx);

      return blockData;
    } catch (e) {
      logger.warning(
        'Error reading block cache for ${originalPath.toString()}: $e',
      );
      // 缓存读取失败，回退到原始文件系统
      final blockData = await _readBlockFromOrigin(
        context,
        originalPath,
        blockIdx,
      );

      // 即使出错也尝试触发预读
      _triggerReadAhead(context, originalPath, blockIdx);

      return blockData;
    }
  }

  /// 从原始文件系统读取指定块
  Future<Uint8List> _readBlockFromOrigin(
    FileSystemContext context,
    Path path,
    int blockIdx,
  ) async {
    final logger = context.logger;

    final blockStart = blockIdx * blockSize;

    // 获取文件大小以确保不会读取超出文件末尾的数据
    final fileStatus = await originFileSystem.stat(context, path);
    final fileSize = fileStatus?.size ?? 0;

    // 计算实际的读取结束位置，不超过文件大小
    final blockEnd = min(blockStart + blockSize, fileSize);

    final readOptions = ReadOptions(start: blockStart, end: blockEnd);

    logger.trace(
      'Reading block $blockIdx from origin for ${path.toString()}: '
      'range $blockStart-$blockEnd (fileSize: $fileSize)',
    );
    return originFileSystem.readAsBytes(context, path, options: readOptions);
  }

  /// 从缓存文件系统读取完整块
  Future<Uint8List?> _readFullBlock(
    FileSystemContext context,
    IFileSystem filesystem,
    Path path,
  ) async {
    final logger = context.logger;

    try {
      return await filesystem.readAsBytes(context, path);
    } catch (e) {
      logger.warning('Failed to read cached block ${path.toString()}: $e');
      return null; // 读取失败返回null
    }
  }

  /// 异步写入缓存（不阻塞主流程）
  void _writeToCacheAsync(
    FileSystemContext context,
    Path cacheHashDir,
    Path cacheBlocksDir,
    Path cacheBlockPath,
    Path cacheMetaPath,
    Path originalPath,
    int blockIdx,
    Uint8List data,
  ) {
    final logger = context.logger;

    // 使用Future.microtask确保不阻塞当前操作
    Future.microtask(() async {
      try {
        // 确保缓存目录结构存在
        if (!await cacheFileSystem.exists(context, cacheHashDir)) {
          await cacheFileSystem.createDirectory(
            context,
            cacheHashDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        if (!await cacheFileSystem.exists(context, cacheBlocksDir)) {
          await cacheFileSystem.createDirectory(
            context,
            cacheBlocksDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        // 写入块数据
        final sink = await cacheFileSystem.openWrite(
          context,
          cacheBlockPath,
          options: const WriteOptions(mode: WriteMode.overwrite),
        );

        sink.add(data);
        await sink.close();

        // 更新或创建meta.json文件
        await _updateCacheMetadata(
          context,
          cacheMetaPath,
          originalPath,
          blockIdx,
        );

        logger.trace(
          'Cache written successfully for ${originalPath.toString()}, '
          'block $blockIdx',
        );
      } catch (e) {
        logger.warning(
          'Failed to write cache for ${originalPath.toString()}, '
          'block $blockIdx: $e',
        );
        // 静默处理缓存写入错误，不影响主流程
      }
    });
  }

  /// 验证缓存完整性，防止hash冲突
  Future<bool> _validateCacheIntegrity(
    FileSystemContext context,
    Path metaPath,
    Path originalPath,
  ) async {
    final logger = context.logger;

    try {
      final metadata = await _readCacheMetadata(context, metaPath);
      if (metadata == null) {
        logger.trace(
          'No metadata file found for cache validation: ${metaPath.toString()}',
        );
        return false;
      }

      // 获取原文件的状态信息进行验证
      final originalStat = await originFileSystem.stat(context, originalPath);
      if (originalStat == null) {
        logger.warning(
          'Original file does not exist: ${originalPath.toString()}',
        );
        return false; // 原文件不存在
      }

      // 使用CacheMetadata的isValid方法进行验证
      final isValid = metadata.isValid(
        expectedPath: originalPath.toString(),
        expectedFileSize: originalStat.size ?? 0,
        expectedBlockSize: blockSize,
      );

      if (!isValid) {
        logger.warning(
          'Cache metadata validation failed for: ${originalPath.toString()}, '
          'metadata: $metadata',
        );
        return false;
      }

      logger.trace(
        'Cache validation passed for ${originalPath.toString()}, '
        'stats: ${metadata.cacheStats}',
      );
      return true;
    } catch (e) {
      logger.warning('Cache integrity validation failed: $e');
      return false;
    }
  }

  /// 读取缓存元数据
  Future<CacheMetadata?> _readCacheMetadata(
    FileSystemContext context,
    Path metaPath,
  ) async {
    final logger = context.logger;

    try {
      if (!await cacheFileSystem.exists(context, metaPath)) {
        return null;
      }

      final metaJson =
          json.decode(
                utf8.decode(
                  await cacheFileSystem.readAsBytes(context, metaPath),
                ),
              )
              as Map<String, dynamic>;
      return CacheMetadata.fromJson(metaJson);
    } catch (e) {
      logger.warning(
        'Failed to read cache metadata from ${metaPath.toString()}: $e',
      );
      return null;
    }
  }

  /// 更新缓存元数据
  Future<void> _updateCacheMetadata(
    FileSystemContext context,
    Path metaPath,
    Path originalPath,
    int blockIdx,
  ) async {
    final logger = context.logger;

    try {
      // 获取原文件信息
      final originalStat = await originFileSystem.stat(context, originalPath);
      if (originalStat == null) {
        logger.warning(
          'Cannot get original file stat for metadata: '
          '${originalPath.toString()}',
        );
        return;
      }

      final fileSize = originalStat.size ?? 0;
      final totalBlocks = (fileSize + blockSize - 1) ~/ blockSize; // 向上取整

      CacheMetadata metadata;

      // 如果元数据文件已存在，先读取现有数据
      final existingMetadata = await _readCacheMetadata(context, metaPath);
      if (existingMetadata != null) {
        metadata = existingMetadata.addCachedBlock(blockIdx);
      } else {
        // 创建新的元数据
        metadata = CacheMetadata(
          filePath: originalPath.toString(),
          fileSize: fileSize,
          blockSize: blockSize,
          totalBlocks: totalBlocks,
          cachedBlocks: {blockIdx},
          lastModified: DateTime.now(),
        );
      }

      // 写入元数据文件
      final metaJson = json.encode(metadata.toJson());
      final metaBytes = utf8.encode(metaJson);

      final sink = await cacheFileSystem.openWrite(
        context,
        metaPath,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      sink.add(metaBytes);
      await sink.close();

      logger.trace(
        'Cache metadata updated for ${originalPath.toString()}, '
        'block $blockIdx, stats: ${metadata.cacheStats}',
      );
    } catch (e) {
      logger.warning('Failed to update cache metadata: $e');
      // 元数据更新失败不影响缓存数据本身
    }
  }

  /// 使指定文件的缓存失效
  Future<void> invalidateCache(FileSystemContext context, Path path) async {
    final logger = context.logger;

    try {
      final cacheHashDir = _buildCacheHashDir(context, path);

      logger.debug(
        'Invalidating cache for path: ${path.toString()}, '
        'cache dir: ${cacheHashDir.toString()}',
      );

      // 清理预读状态
      _cleanupReadAheadState(context, path);

      // 检查缓存目录是否存在
      if (await cacheFileSystem.exists(context, cacheHashDir)) {
        // 删除整个hash目录（包含blocks子目录和meta.json文件）
        await cacheFileSystem.delete(
          context,
          cacheHashDir,
          options: const DeleteOptions(recursive: true),
        );
        logger.debug('Cache invalidated successfully for: ${path.toString()}');

        // 尝试清理空的父级目录
        await _cleanupEmptyParentDirs(context, cacheHashDir);
      } else {
        logger.trace('No cache found to invalidate for: ${path.toString()}');
      }
    } catch (e) {
      logger.warning('Failed to invalidate cache for ${path.toString()}: $e');
      // 静默处理缓存清理错误，不影响主流程
    }
  }

  /// 清理空的父级目录（避免留下大量空目录）
  Future<void> _cleanupEmptyParentDirs(
    FileSystemContext context,
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
        final level2Items = <FileStatus>[];
        await for (final item in cacheFileSystem.list(context, level2Dir)) {
          level2Items.add(item);
        }

        if (level2Items.isEmpty) {
          await cacheFileSystem.delete(context, level2Dir);
          logger.trace('Cleaned up empty level2 dir: ${level2Dir.toString()}');

          // 检查level1目录是否也为空
          if (level1Dir != null &&
              await cacheFileSystem.exists(context, level1Dir)) {
            final level1Items = <FileStatus>[];
            await for (final item in cacheFileSystem.list(context, level1Dir)) {
              level1Items.add(item);
            }

            if (level1Items.isEmpty) {
              await cacheFileSystem.delete(context, level1Dir);
              logger.trace(
                'Cleaned up empty level1 dir: ${level1Dir.toString()}',
              );
            }
          }
        }
      }
    } catch (e) {
      // 静默处理清理错误，不影响主要功能
      logger.trace('Failed to cleanup empty parent dirs: $e');
    }
  }

  /// 触发预读操作
  void _triggerReadAhead(
    FileSystemContext context,
    Path originalPath,
    int currentBlockIdx,
  ) {
    final logger = context.logger;

    if (!enableReadAhead || readAheadBlocks <= 0) {
      return;
    }

    final pathString = originalPath.toString();

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
        'Non-sequential access detected for ${originalPath.toString()}: '
        'last=$lastBlock, current=$currentBlockIdx, skipping read-ahead',
      );
      return;
    }

    // 异步执行预读
    _performReadAhead(context, originalPath, currentBlockIdx);
  }

  /// 执行预读操作
  void _performReadAhead(
    FileSystemContext context,
    Path originalPath,
    int currentBlockIdx,
  ) {
    final logger = context.logger;

    Future.microtask(() async {
      final pathString = originalPath.toString();

      try {
        // 获取文件大小来确定有效的块范围
        final fileStatus = await originFileSystem.stat(context, originalPath);
        if (fileStatus == null) {
          return;
        }

        final fileSize = fileStatus.size ?? 0;
        final maxBlockIdx = (fileSize + blockSize - 1) ~/ blockSize - 1;

        // 初始化活跃任务集合
        _activeReadAheadTasks[pathString] ??= <int>{};
        final activeTasks = _activeReadAheadTasks[pathString]!;

        final cacheHashDir = _buildCacheHashDir(context, originalPath);
        final cacheBlocksDir = cacheHashDir.join('blocks');
        final cacheMetaPath = cacheHashDir.join('meta.json');

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
          final cacheBlockPath = cacheBlocksDir.join(targetBlockIdx.toString());
          if (await cacheFileSystem.exists(context, cacheBlockPath)) {
            continue;
          }

          // 添加到活跃任务并开始预读
          activeTasks.add(targetBlockIdx);

          readAheadTasks.add(
            _readAheadBlock(
              context,
              originalPath,
              targetBlockIdx,
              cacheHashDir,
              cacheBlocksDir,
              cacheBlockPath,
              cacheMetaPath,
            ),
          );
        }

        // 等待所有预读任务完成（但不阻塞主流程）
        if (readAheadTasks.isNotEmpty) {
          logger.trace(
            'Starting read-ahead for ${originalPath.toString()}: '
            '${readAheadTasks.length} blocks after block $currentBlockIdx',
          );

          await Future.wait(readAheadTasks);

          logger.trace(
            'Completed read-ahead for ${originalPath.toString()}: '
            '${readAheadTasks.length} blocks',
          );
        }
      } catch (e) {
        logger.warning('Read-ahead failed for ${originalPath.toString()}: $e');
      }
    });
  }

  /// 预读单个块
  Future<void> _readAheadBlock(
    FileSystemContext context,
    Path originalPath,
    int blockIdx,
    Path cacheHashDir,
    Path cacheBlocksDir,
    Path cacheBlockPath,
    Path cacheMetaPath,
  ) async {
    final logger = context.logger;

    final pathString = originalPath.toString();

    try {
      logger.trace(
        'Read-ahead: fetching block $blockIdx for ${originalPath.toString()}',
      );

      // 从原始文件系统读取块数据
      final blockData = await _readBlockFromOrigin(
        context,
        originalPath,
        blockIdx,
      );

      // 确保缓存目录结构存在
      if (!await cacheFileSystem.exists(context, cacheHashDir)) {
        await cacheFileSystem.createDirectory(
          context,
          cacheHashDir,
          options: const CreateDirectoryOptions(createParents: true),
        );
      }

      if (!await cacheFileSystem.exists(context, cacheBlocksDir)) {
        await cacheFileSystem.createDirectory(
          context,
          cacheBlocksDir,
          options: const CreateDirectoryOptions(createParents: true),
        );
      }

      // 写入块数据到缓存
      final sink = await cacheFileSystem.openWrite(
        context,
        cacheBlockPath,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      sink.add(blockData);
      await sink.close();

      // 更新元数据
      await _updateCacheMetadata(
        context,
        cacheMetaPath,
        originalPath,
        blockIdx,
      );

      logger.trace(
        'Read-ahead: successfully cached block $blockIdx '
        'for ${originalPath.toString()}',
      );
    } catch (e) {
      logger.warning(
        'Read-ahead: failed to cache block $blockIdx '
        'for ${originalPath.toString()}: $e',
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
  void _cleanupReadAheadState(FileSystemContext context, Path originalPath) {
    final logger = context.logger;
    final pathString = originalPath.toString();
    _activeReadAheadTasks.remove(pathString);
    _lastAccessedBlock.remove(pathString);

    logger.trace('Cleaned up read-ahead state for ${originalPath.toString()}');
  }
}
