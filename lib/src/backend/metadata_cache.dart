import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import '../abstract/index.dart';

class MetadataCacheFileSystem extends IFileSystem {
  MetadataCacheFileSystem({
    required this.originFileSystem,
    required this.cacheFileSystem,
    required this.cacheDir,
    String loggerName = 'MetadataCacheFileSystem',
  }) : logger = Logger(loggerName);

  @override
  final Logger logger;
  final IFileSystem originFileSystem;
  final IFileSystem cacheFileSystem;
  final Path cacheDir;

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

  /// 将FileStatus序列化为Map
  Map<String, dynamic> _fileStatusToMap(FileStatus status) {
    return {
      'path': status.path.toString(),
      'isDirectory': status.isDirectory,
      'size': status.size,
      'mimeType': status.mimeType,
    };
  }

  /// 从Map反序列化FileStatus
  FileStatus _fileStatusFromMap(Map<String, dynamic> map) {
    return FileStatus(
      path: Path.fromString(map['path'] as String),
      isDirectory: map['isDirectory'] as bool,
      size: map['size'] as int?,
      mimeType: map['mimeType'] as String?,
    );
  }

  /// 读取缓存的元数据
  Future<Map<String, dynamic>?> _readCachedMetadata(Path path) async {
    try {
      final cacheFilePath = _buildCacheHashDir(path);

      if (!await cacheFileSystem.exists(cacheFilePath)) {
        return null;
      }

      final data = await cacheFileSystem.readAsBytes(cacheFilePath);
      final jsonStr = utf8.decode(data);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null; // 缓存读取失败
    }
  }

  /// 写入缓存的元数据
  Future<void> _writeCachedMetadata(
    Path path,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final cacheFilePath = _buildCacheHashDir(path);

      // 确保缓存目录存在
      final cacheParentDir = cacheFilePath.parent;
      if (cacheParentDir != null &&
          !await cacheFileSystem.exists(cacheParentDir)) {
        await cacheFileSystem.createDirectory(
          cacheParentDir,
          options: const CreateDirectoryOptions(createParents: true),
        );
      }

      final jsonStr = jsonEncode(metadata);
      final data = utf8.encode(jsonStr);
      await cacheFileSystem.writeBytes(cacheFilePath, Uint8List.fromList(data));
    } catch (e) {
      // 静默处理缓存写入错误
    }
  }

  /// 使缓存失效
  Future<void> _invalidateCache(Path path) async {
    try {
      final cacheFilePath = _buildCacheHashDir(path);
      if (await cacheFileSystem.exists(cacheFilePath)) {
        await cacheFileSystem.delete(cacheFilePath);
      }
    } catch (e) {
      // 静默处理缓存删除错误
    }
  }

  /// 刷新路径的元数据缓存
  Future<void> _refreshMetadataCache(Path path) async {
    try {
      final status = await originFileSystem.stat(path);
      if (status == null) {
        await _invalidateCache(path);
        return;
      }

      final metadata = <String, dynamic>{
        'stat': _fileStatusToMap(status),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };

      // 如果是目录，根据策略决定是否缓存子文件列表
      if (status.isDirectory) {
        // 传统方式：缓存所有子文件
        final children = <Map<String, dynamic>>[];
        await for (final child in originFileSystem.list(path)) {
          children.add(_fileStatusToMap(child));
        }
        metadata['children'] = children;
      }

      await _writeCachedMetadata(path, metadata);
    } catch (e) {
      // 刷新失败时删除缓存
      await _invalidateCache(path);
    }
  }

  @override
  Future<void> copy(
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    await originFileSystem.copy(source, destination, options: options);
    // 目标文件的缓存需要刷新，源文件缓存保持不变
    await _refreshMetadataCache(destination);
    // 如果目标路径的父目录存在缓存，也需要刷新
    final parentPath = destination.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(parentPath);
    }
  }

  @override
  Future<void> createDirectory(
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    await originFileSystem.createDirectory(path, options: options);
    // 新创建的目录需要刷新缓存
    await _refreshMetadataCache(path);
    // 父目录的子文件列表也需要刷新
    final parentPath = path.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(parentPath);
    }
  }

  @override
  Future<void> delete(
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    await originFileSystem.delete(path, options: options);
    // 删除文件后使其缓存失效
    await _invalidateCache(path);
    // 父目录的子文件列表也需要刷新
    final parentPath = path.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(parentPath);
    }
  }

  @override
  Future<bool> exists(
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    // exists可以通过stat实现
    final status = await stat(path);
    return status != null;
  }

  @override
  Future<void> move(
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    await originFileSystem.move(source, destination, options: options);
    // 移动操作：源文件缓存失效，目标文件缓存刷新
    await _invalidateCache(source);
    await _refreshMetadataCache(destination);
    // 源文件和目标文件的父目录都需要刷新
    final sourceParent = source.parent;
    if (sourceParent != null) {
      await _refreshMetadataCache(sourceParent);
    }
    final destParent = destination.parent;
    if (destParent != null) {
      await _refreshMetadataCache(destParent);
    }
  }

  @override
  Stream<List<int>> openRead(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.openRead(path, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    final originalSink = await originFileSystem.openWrite(
      path,
      options: options,
    );

    // 创建一个装饰器Sink，在写入完成后刷新缓存
    return _MetadataInvalidatingSink(
      originalSink: originalSink,
      onClose: () async {
        await _refreshMetadataCache(path);
        // 父目录的子文件列表也可能需要刷新（新文件创建的情况）
        final parentPath = path.parent;
        if (parentPath != null) {
          await _refreshMetadataCache(parentPath);
        }
      },
    );
  }

  @override
  Future<Uint8List> readAsBytes(
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不影响元数据，直接代理
    return originFileSystem.readAsBytes(path, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    try {
      // 首先尝试从缓存读取
      final cachedMetadata = await _readCachedMetadata(path);
      if (cachedMetadata != null) {
        final statData = cachedMetadata['stat'] as Map<String, dynamic>?;
        if (statData != null) {
          return _fileStatusFromMap(statData);
        }
      }

      // 缓存不存在或无效，从原始文件系统获取
      final status = await originFileSystem.stat(path, options: options);

      // 异步更新缓存
      if (status != null) {
        unawaited(_refreshMetadataCache(path));
      }

      return status;
    } catch (e) {
      // 出错时回退到原始文件系统
      return originFileSystem.stat(path, options: options);
    }
  }

  @override
  Stream<FileStatus> list(
    Path path, {
    ListOptions options = const ListOptions(),
  }) async* {
    try {
      // 首先尝试从缓存读取
      final cachedMetadata = await _readCachedMetadata(path);
      if (cachedMetadata != null) {
        // 检查是否是大目录
        final isLargeDirectory =
            cachedMetadata['isLargeDirectory'] as bool? ?? false;

        if (!isLargeDirectory) {
          // 普通目录，从缓存读取子文件列表
          final children = cachedMetadata['children'] as List<dynamic>?;
          if (children != null) {
            for (final child in children) {
              yield _fileStatusFromMap(child as Map<String, dynamic>);
            }
            return;
          }
        }
        // 大目录不使用缓存的子文件列表，直接从原始文件系统读取
      }

      // 缓存不存在、无效或是大目录，从原始文件系统获取
      await for (final item in originFileSystem.list(path, options: options)) {
        yield item;
      }

      // 异步更新缓存（如果是大目录，这里会适当处理）
      unawaited(_refreshMetadataCache(path));
    } catch (e) {
      // 出错时回退到原始文件系统
      await for (final item in originFileSystem.list(path, options: options)) {
        yield item;
      }
    }
  }

  @override
  Future<void> writeBytes(
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    await originFileSystem.writeBytes(path, data, options: options);
    // 写入完成后刷新缓存
    await _refreshMetadataCache(path);
    // 父目录的子文件列表也可能需要刷新（新文件创建的情况）
    final parentPath = path.parent;
    if (parentPath != null) {
      await _refreshMetadataCache(parentPath);
    }
  }
}

/// 装饰器Sink，在写入完成后执行回调
class _MetadataInvalidatingSink implements StreamSink<List<int>> {
  _MetadataInvalidatingSink({
    required this.originalSink,
    required this.onClose,
  });

  final StreamSink<List<int>> originalSink;
  final Future<void> Function() onClose;

  @override
  void add(List<int> data) {
    originalSink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    originalSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return originalSink.addStream(stream);
  }

  @override
  Future<void> close() async {
    // 先关闭原始Sink
    await originalSink.close();
    // 然后执行缓存刷新回调
    await onClose();
  }

  @override
  Future<void> get done => originalSink.done;
}
