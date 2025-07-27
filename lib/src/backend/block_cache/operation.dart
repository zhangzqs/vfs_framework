import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import '../../abstract/index.dart';
import 'metadata.dart';

class CacheOperation {
  CacheOperation({
    required this.logger,
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    required this.blockSize,
  });
  final Logger logger;
  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;
  final int blockSize;

  /// 基于SHA256生成文件路径的hash值，16个字符
  String _generatePathHash(Path path) {
    // hash为长度为16的字符串
    final pathString = path.toString();
    final bytes = utf8.encode(pathString);
    final digest = sha256.convert(bytes);

    // 使用SHA-256的前16位作为hash值，大大降低冲突概率
    final hash = digest.toString().substring(0, 16);
    logger.finest('Generated hash for ${path.toString()}: $hash');
    return hash;
  }

  /// 在cacheDir中，针对srcPath构建分层缓存目录路径，双层目录结构，有利于文件系统查询性能
  Path _buildCacheHashDir(Path path) {
    final hash = _generatePathHash(path);
    // 使用前2位作为第一层目录 (每个level1下4096种可能)
    final level1 = hash.substring(0, 3);
    // 使用第3-4位作为第二层目录 (每个level2下4096种可能)
    final level2 = hash.substring(3, 6);
    // 第三级目录使用剩余的hash值
    final level3 = hash.substring(6);
    // 构建分层路径: cacheDir/abc/def/1234ef567890/
    final hierarchicalPath = cacheDir.join(level1).join(level2).join(level3);

    logger.finest(
      'Built hierarchical cache path for hash $hash: '
      '${hierarchicalPath.toString()}',
    );
    return hierarchicalPath;
  }

  /// 实现块缓存的读取
  Stream<List<int>> openReadWithBlockCache(
    Path path,
    ReadOptions options,
  ) async* {
    logger.finest('Starting block-cached read for ${path.toString()}');

    // 获取文件状态信息
    final fileStatus = await originFileSystem.stat(path);
    if (fileStatus == null) {
      throw FileSystemException.notFound(path);
    }
    if (fileStatus.isDirectory) {
      throw FileSystemException.notAFile(path);
    }
    final fileSize = fileStatus.size ?? 0;
    if (fileSize == 0) {
      logger.finest('File is empty: ${path.toString()}');
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

    logger.finest(
      'Reading ${path.toString()}: blocks $startBlockIdx-$endBlockIdx '
      '($totalBlocks blocks)',
    );

    // 生成文件路径的hash
    final cacheHashDir = _buildCacheHashDir(path);

    // 逐块读取数据
    var currentOffset = startOffset;
    var remainingBytes = readLength;

    for (var blockIdx = startBlockIdx; blockIdx <= endBlockIdx; blockIdx++) {
      if (remainingBytes <= 0) break;

      // 获取当前块的数据
      final blockData = await _getBlockData(cacheHashDir, blockIdx, path);

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

    logger.finest('Completed block-cached read for ${path.toString()}');
  }

  /// 获取指定块的数据（带缓存）
  Future<Uint8List> _getBlockData(
    Path cacheHashDir,
    int blockIdx,
    Path originalPath,
  ) async {
    // 构建分层缓存路径：<cacheHashDir>/blocks/<blockIdx> 和 <cacheHashDir>/meta.json
    final cacheBlocksDir = cacheHashDir.join('blocks');
    final cacheBlockPath = cacheBlocksDir.join(blockIdx.toString());
    final cacheMetaPath = cacheHashDir.join('meta.json');

    try {
      // 首先检查缓存是否存在
      if (await cacheFileSystem.exists(cacheBlockPath)) {
        // 验证缓存完整性和hash冲突
        if (await _validateCacheIntegrity(cacheMetaPath, originalPath)) {
          final cachedData = await _readFullBlock(
            cacheFileSystem,
            cacheBlockPath,
          );
          if (cachedData != null) {
            logger.finest(
              'Cache hit for ${originalPath.toString()}, block $blockIdx',
            );
            return cachedData;
          }
        } else {
          logger.warning(
            'Cache integrity check failed for ${originalPath.toString()}, '
            'possible hash collision detected, invalidating cache',
          );
          await invalidateCache(originalPath);
        }
      }

      // 缓存不存在或验证失败，从原始文件系统读取
      logger.finest(
        'Cache miss for ${originalPath.toString()}, block $blockIdx, '
        'reading from origin',
      );
      final blockData = await _readBlockFromOrigin(originalPath, blockIdx);

      // 异步写入缓存（不阻塞读取）
      _writeToCacheAsync(
        cacheHashDir,
        cacheBlocksDir,
        cacheBlockPath,
        cacheMetaPath,
        originalPath,
        blockIdx,
        blockData,
      );

      return blockData;
    } catch (e) {
      logger.warning(
        'Error reading block cache for ${originalPath.toString()}: $e',
      );
      // 缓存读取失败，回退到原始文件系统
      return await _readBlockFromOrigin(originalPath, blockIdx);
    }
  }

  /// 从原始文件系统读取指定块
  Future<Uint8List> _readBlockFromOrigin(Path path, int blockIdx) async {
    final blockStart = blockIdx * blockSize;

    // 获取文件大小以确保不会读取超出文件末尾的数据
    final fileStatus = await originFileSystem.stat(path);
    final fileSize = fileStatus?.size ?? 0;

    // 计算实际的读取结束位置，不超过文件大小
    final blockEnd = min(blockStart + blockSize, fileSize);

    final readOptions = ReadOptions(start: blockStart, end: blockEnd);

    logger.finest(
      'Reading block $blockIdx from origin for ${path.toString()}: '
      'range $blockStart-$blockEnd (fileSize: $fileSize)',
    );

    final chunks = <int>[];
    await for (final chunk in originFileSystem.openRead(
      path,
      options: readOptions,
    )) {
      chunks.addAll(chunk);
    }

    return Uint8List.fromList(chunks);
  }

  /// 从缓存文件系统读取完整块
  Future<Uint8List?> _readFullBlock(IFileSystem filesystem, Path path) async {
    try {
      final chunks = <int>[];
      await for (final chunk in filesystem.openRead(path)) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (e) {
      logger.warning('Failed to read cached block ${path.toString()}: $e');
      return null; // 读取失败返回null
    }
  }

  /// 异步写入缓存（不阻塞主流程）
  void _writeToCacheAsync(
    Path cacheHashDir,
    Path cacheBlocksDir,
    Path cacheBlockPath,
    Path cacheMetaPath,
    Path originalPath,
    int blockIdx,
    Uint8List data,
  ) {
    // 使用Future.microtask确保不阻塞当前操作
    Future.microtask(() async {
      try {
        // 确保缓存目录结构存在
        if (!await cacheFileSystem.exists(cacheHashDir)) {
          await cacheFileSystem.createDirectory(
            cacheHashDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        if (!await cacheFileSystem.exists(cacheBlocksDir)) {
          await cacheFileSystem.createDirectory(
            cacheBlocksDir,
            options: const CreateDirectoryOptions(createParents: true),
          );
        }

        // 写入块数据
        final sink = await cacheFileSystem.openWrite(
          cacheBlockPath,
          options: const WriteOptions(mode: WriteMode.overwrite),
        );

        sink.add(data);
        await sink.close();

        // 更新或创建meta.json文件
        await _updateCacheMetadata(cacheMetaPath, originalPath, blockIdx);

        logger.finest(
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
  Future<bool> _validateCacheIntegrity(Path metaPath, Path originalPath) async {
    try {
      final metadata = await _readCacheMetadata(metaPath);
      if (metadata == null) {
        logger.finest(
          'No metadata file found for cache validation: ${metaPath.toString()}',
        );
        return false;
      }

      // 获取原文件的状态信息进行验证
      final originalStat = await originFileSystem.stat(originalPath);
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

      logger.finest(
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
  Future<CacheMetadata?> _readCacheMetadata(Path metaPath) async {
    try {
      if (!await cacheFileSystem.exists(metaPath)) {
        return null;
      }

      final metaBytes = <int>[];
      await for (final chunk in cacheFileSystem.openRead(metaPath)) {
        metaBytes.addAll(chunk);
      }

      final metaJson =
          json.decode(utf8.decode(metaBytes)) as Map<String, dynamic>;
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
    Path metaPath,
    Path originalPath,
    int blockIdx,
  ) async {
    try {
      // 获取原文件信息
      final originalStat = await originFileSystem.stat(originalPath);
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
      final existingMetadata = await _readCacheMetadata(metaPath);
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
        metaPath,
        options: const WriteOptions(mode: WriteMode.overwrite),
      );

      sink.add(metaBytes);
      await sink.close();

      logger.finest(
        'Cache metadata updated for ${originalPath.toString()}, '
        'block $blockIdx, stats: ${metadata.cacheStats}',
      );
    } catch (e) {
      logger.warning('Failed to update cache metadata: $e');
      // 元数据更新失败不影响缓存数据本身
    }
  }

  /// 使指定文件的缓存失效
  Future<void> invalidateCache(Path path) async {
    try {
      final cacheHashDir = _buildCacheHashDir(path);

      logger.fine(
        'Invalidating cache for path: ${path.toString()}, '
        'cache dir: ${cacheHashDir.toString()}',
      );

      // 检查缓存目录是否存在
      if (await cacheFileSystem.exists(cacheHashDir)) {
        // 删除整个hash目录（包含blocks子目录和meta.json文件）
        await cacheFileSystem.delete(
          cacheHashDir,
          options: const DeleteOptions(recursive: true),
        );
        logger.fine('Cache invalidated successfully for: ${path.toString()}');

        // 尝试清理空的父级目录
        await _cleanupEmptyParentDirs(cacheHashDir);
      } else {
        logger.finest('No cache found to invalidate for: ${path.toString()}');
      }
    } catch (e) {
      logger.warning('Failed to invalidate cache for ${path.toString()}: $e');
      // 静默处理缓存清理错误，不影响主流程
    }
  }

  /// 清理空的父级目录（避免留下大量空目录）
  Future<void> _cleanupEmptyParentDirs(Path cacheHashDir) async {
    try {
      // 获取父级目录路径
      final level2Dir = cacheHashDir.parent; // xx/yy/ 目录
      final level1Dir = level2Dir?.parent; // xx/ 目录

      if (level2Dir != null && await cacheFileSystem.exists(level2Dir)) {
        // 检查level2目录是否为空
        final level2Items = <FileStatus>[];
        await for (final item in cacheFileSystem.list(level2Dir)) {
          level2Items.add(item);
        }

        if (level2Items.isEmpty) {
          await cacheFileSystem.delete(level2Dir);
          logger.finest('Cleaned up empty level2 dir: ${level2Dir.toString()}');

          // 检查level1目录是否也为空
          if (level1Dir != null && await cacheFileSystem.exists(level1Dir)) {
            final level1Items = <FileStatus>[];
            await for (final item in cacheFileSystem.list(level1Dir)) {
              level1Items.add(item);
            }

            if (level1Items.isEmpty) {
              await cacheFileSystem.delete(level1Dir);
              logger.finest(
                'Cleaned up empty level1 dir: ${level1Dir.toString()}',
              );
            }
          }
        }
      }
    } catch (e) {
      // 静默处理清理错误，不影响主要功能
      logger.finest('Failed to cleanup empty parent dirs: $e');
    }
  }
}
