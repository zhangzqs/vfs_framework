import 'dart:async';

import 'dart:typed_data';

import '../abstract/index.dart';

class QuotaLimitConfig {
  const QuotaLimitConfig({
    this.maxEntities,
    this.maxTotalSize,
    this.maxFileSize,
  });

  /// 最大实体数量限制（包括文件和目录）
  final int? maxEntities;

  /// 最大总大小限制（字节）
  final int? maxTotalSize;

  /// 单个文件最大大小限制（字节）
  final int? maxFileSize;

  /// 创建无限制的配额
  static const QuotaLimitConfig unlimited = QuotaLimitConfig();

  /// 创建默认配额：最多10000个实体，总大小100MB，单文件10MB
  static const QuotaLimitConfig defaultQuota = QuotaLimitConfig(
    maxEntities: 10000,
    maxTotalSize: 100 * 1024 * 1024, // 100MB
    maxFileSize: 10 * 1024 * 1024, // 10MB
  );

  @override
  String toString() {
    return {
      'maxEntities': maxEntities,
      'maxTotalSize': maxTotalSize,
      'maxFileSize': maxFileSize,
    }.toString();
  }
}

/// 配额管理器，负责检查和强制执行配额限制
class QuotaManager {
  QuotaManager(this.quota, this.quotaFileSystem);

  final QuotaLimitConfig quota;
  final IQuotaFileSystem quotaFileSystem;

  /// 检查是否可以创建新实体
  Future<void> checkCanCreateEntity(Context context) async {
    final currentEntities = await quotaFileSystem.getQuotaInfo(context);
    if (quota.maxEntities != null &&
        currentEntities.entityCount >= quota.maxEntities!) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Entity count quota exceeded: ${quota.maxEntities}',
      );
    }
  }

  /// 检查是否可以写入指定大小的数据
  Future<void> checkCanWriteData(Context context, int dataSize) async {
    final currentQuota = await quotaFileSystem.getQuotaInfo(context);
    final currentTotalSize = currentQuota.totalSize;
    // 检查单文件大小限制
    if (quota.maxFileSize != null && dataSize > quota.maxFileSize!) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'File size quota exceeded: ${quota.maxFileSize} bytes',
      );
    }

    // 检查总大小限制
    if (quota.maxTotalSize != null &&
        (currentTotalSize + dataSize) > quota.maxTotalSize!) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message: 'Total size quota exceeded: ${quota.maxTotalSize} bytes',
      );
    }
  }

  /// 检查是否可以追加数据到现有文件
  Future<void> checkCanAppendData(
    Context context,
    int appendSize,
    int existingFileSize,
  ) async {
    final currentQuota = await quotaFileSystem.getQuotaInfo(context);
    final currentTotalSize = currentQuota.totalSize;
    final newFileSize = existingFileSize + appendSize;

    // 检查单文件大小限制
    if (quota.maxFileSize != null && newFileSize > quota.maxFileSize!) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message:
            'File size quota exceeded after append: ${quota.maxFileSize} bytes',
      );
    }

    // 检查总大小限制（只考虑新增的部分）
    if (quota.maxTotalSize != null &&
        (currentTotalSize + appendSize) > quota.maxTotalSize!) {
      throw FileSystemException(
        code: FileSystemErrorCode.ioError,
        message:
            'Total size quota exceeded after append: '
            '${quota.maxTotalSize} bytes',
      );
    }
  }

  /// 获取配额使用情况
  Map<String, dynamic> getQuotaUsage(
    int currentEntities,
    int currentTotalSize,
  ) {
    return {
      'quota': {
        'maxEntities': quota.maxEntities,
        'maxTotalSize': quota.maxTotalSize,
        'maxFileSize': quota.maxFileSize,
      },
      'current': {'entities': currentEntities, 'totalSize': currentTotalSize},
      'usage': {
        'entitiesPercent': quota.maxEntities != null
            ? (currentEntities / quota.maxEntities! * 100).toStringAsFixed(2)
            : 'unlimited',
        'totalSizePercent': quota.maxTotalSize != null
            ? (currentTotalSize / quota.maxTotalSize! * 100).toStringAsFixed(2)
            : 'unlimited',
      },
    };
  }
}

class QuotaLimitFileSystem implements IFileSystem {
  QuotaLimitFileSystem({
    required this.originFileSystem,
    required this.quotaFileSystem,
    required QuotaLimitConfig quotaLimitConfig,
  }) : quotaManager = QuotaManager(quotaLimitConfig, quotaFileSystem);
  final IFileSystem originFileSystem;
  final IQuotaFileSystem quotaFileSystem;
  final QuotaManager quotaManager;

  @override
  Future<void> copy(
    Context context,
    Path source,
    Path destination, {
    CopyOptions options = const CopyOptions(),
  }) async {
    // 在复制前检查配额（如果是创建新实体）
    if (!await originFileSystem.exists(context, destination)) {
      await quotaManager.checkCanCreateEntity(context);
    }

    // 如果是文件复制，检查大小限制
    final sourceStat = await originFileSystem.stat(context, source);
    if (sourceStat != null &&
        !sourceStat.isDirectory &&
        sourceStat.size != null) {
      await quotaManager.checkCanWriteData(context, sourceStat.size!);
    }

    return originFileSystem.copy(
      context,
      source,
      destination,
      options: options,
    );
  }

  @override
  Future<void> createDirectory(
    Context context,
    Path path, {
    CreateDirectoryOptions options = const CreateDirectoryOptions(),
  }) async {
    // 检查是否可以创建新实体
    await quotaManager.checkCanCreateEntity(context);

    return originFileSystem.createDirectory(context, path, options: options);
  }

  @override
  Future<void> delete(
    Context context,
    Path path, {
    DeleteOptions options = const DeleteOptions(),
  }) async {
    // 删除操作不需要配额检查，直接委托
    return originFileSystem.delete(context, path, options: options);
  }

  @override
  Future<bool> exists(
    Context context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    // 存在性检查不需要配额检查，直接委托
    return originFileSystem.exists(context, path, options: options);
  }

  @override
  Stream<FileStatus> list(
    Context context,
    Path path, {
    ListOptions options = const ListOptions(),
  }) {
    // 列表操作不需要配额检查，直接委托
    return originFileSystem.list(context, path, options: options);
  }

  @override
  Future<void> move(
    Context context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    // 移动操作通常不增加新实体，但如果跨文件系统可能需要检查
    // 这里简化处理，直接委托
    return originFileSystem.move(
      context,
      source,
      destination,
      options: options,
    );
  }

  @override
  Stream<List<int>> openRead(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) {
    // 读取操作不需要配额检查，直接委托
    return originFileSystem.openRead(context, path, options: options);
  }

  @override
  Future<StreamSink<List<int>>> openWrite(
    Context context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    // 检查是否是新文件
    final fileExists = await originFileSystem.exists(context, path);
    if (!fileExists) {
      await quotaManager.checkCanCreateEntity(context);
    }

    // 注意：这里只能做初步检查，实际写入的数据大小在流操作时才知道
    // 在真实实现中，可能需要包装返回的 StreamSink 来进行配额检查
    return originFileSystem.openWrite(context, path, options: options);
  }

  @override
  Future<Uint8List> readAsBytes(
    Context context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async {
    // 读取操作不需要配额检查，直接委托
    return originFileSystem.readAsBytes(context, path, options: options);
  }

  @override
  Future<FileStatus?> stat(
    Context context,
    Path path, {
    StatOptions options = const StatOptions(),
  }) async {
    // 状态查询不需要配额检查，直接委托
    return originFileSystem.stat(context, path, options: options);
  }

  @override
  Future<void> writeBytes(
    Context context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) async {
    // 检查是否是新文件
    final fileExists = await originFileSystem.exists(context, path);
    if (!fileExists) {
      await quotaManager.checkCanCreateEntity(context);
      await quotaManager.checkCanWriteData(context, data.length);
    } else {
      // 对于已存在的文件，需要根据写入模式检查
      if (options.mode == WriteMode.append) {
        final currentStat = await originFileSystem.stat(context, path);
        final existingSize = currentStat?.size ?? 0;
        await quotaManager.checkCanAppendData(
          context,
          data.length,
          existingSize,
        );
      } else {
        // 覆盖模式，检查新文件大小
        await quotaManager.checkCanWriteData(context, data.length);
      }
    }

    return originFileSystem.writeBytes(context, path, data, options: options);
  }

  @override
  Future<void> dispose(Context context) async {
    await originFileSystem.dispose(context);
  }
}
