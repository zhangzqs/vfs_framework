import 'path.dart';

/// 错误码枚举
enum FileSystemErrorCode {
  notFound, // 文件或目录未找到
  notAFile, // 目标不是文件
  notADirectory, // 目标不是目录
  unsupportedEntity, // 不支持的实体操作类型
  ioError, // 其他 IO 错误
  permissionDenied, // 权限被拒绝
  alreadyExists, // 目标实体已存在
  notEmptyDirectory, // 目录不为空
  recursiveNotSpecified, // 递归操作未指定
  readOnly, // 文件系统为只读
}

/// 统一文件系统异常
class FileSystemException implements Exception {
  final FileSystemErrorCode code;
  final String message;
  final Path? path;
  final Path? otherPath;

  const FileSystemException({
    required this.code,
    required this.message,
    this.path,
    this.otherPath,
  });

  // 快捷构造函数
  factory FileSystemException.notFound(Path path) => FileSystemException(
    code: FileSystemErrorCode.notFound,
    message: 'File or directory not found',
    path: path,
  );
  factory FileSystemException.notAFile(Path path) => FileSystemException(
    code: FileSystemErrorCode.notAFile,
    message: 'Target is not a file',
    path: path,
  );

  factory FileSystemException.notADirectory(Path path) => FileSystemException(
    code: FileSystemErrorCode.notADirectory,
    message: 'Target is not a directory',
    path: path,
  );

  factory FileSystemException.permissionDenied(Path path) =>
      FileSystemException(
        code: FileSystemErrorCode.permissionDenied,
        message: 'Permission denied',
        path: path,
      );
  factory FileSystemException.unsupportedEntity(Path path) =>
      FileSystemException(
        code: FileSystemErrorCode.unsupportedEntity,
        message: 'Unsupported entity type',
        path: path,
      );
  factory FileSystemException.alreadyExists(Path path, {String? message}) =>
      FileSystemException(
        code: FileSystemErrorCode.alreadyExists,
        message: message ?? 'Entity already exists',
        path: path,
      );
  factory FileSystemException.notEmptyDirectory(Path path) =>
      FileSystemException(
        code: FileSystemErrorCode.notEmptyDirectory,
        message: 'Directory is not empty',
        path: path,
      );
  factory FileSystemException.recursiveNotSpecified(Path path) =>
      FileSystemException(
        code: FileSystemErrorCode.recursiveNotSpecified,
        message: 'Recursive option not specified, omitting directory $path',
        path: path,
      );
  factory FileSystemException.readOnly(Path path) => FileSystemException(
    code: FileSystemErrorCode.readOnly,
    message: 'File system is read-only',
    path: path,
  );
  @override
  String toString() => 'FileSystemException($code, $path): $message';
}
