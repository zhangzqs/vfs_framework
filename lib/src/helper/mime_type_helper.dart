/// 扩展名到MIME类型的映射
const Map<String, String> _extensionToMimeType = {
  // 文本文件
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.html': 'text/html',
  '.htm': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.csv': 'text/csv',

  // 图片文件
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',

  // 音频文件
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.m4a': 'audio/mp4',

  // 视频文件
  '.mp4': 'video/mp4',
  '.avi': 'video/x-msvideo',
  '.mov': 'video/quicktime',
  '.wmv': 'video/x-ms-wmv',
  '.flv': 'video/x-flv',

  // 文档文件
  '.pdf': 'application/pdf',
  '.doc': 'application/msword',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint',
  '.pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',

  // 压缩文件
  '.zip': 'application/zip',
  '.rar': 'application/x-rar-compressed',
  '.7z': 'application/x-7z-compressed',
  '.tar': 'application/x-tar',
  '.gz': 'application/gzip',

  // 程序文件
  '.exe': 'application/x-msdownload',
  '.dmg': 'application/x-apple-diskimage',
  '.deb': 'application/x-debian-package',
  '.rpm': 'application/x-rpm',
};

/// 根据文件名获取MIME类型
///
/// 返回与给定文件名扩展名对应的MIME类型。
/// 如果文件名没有扩展名或扩展名不被识别，则返回null。
///
/// 示例:
/// ```dart
/// detectMimeType('document.pdf'); // 返回 'application/pdf'
/// detectMimeType('image.jpg');    // 返回 'image/jpeg'
/// detectMimeType('unknown');      // 返回 null
/// ```
String? detectMimeType(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex == -1) return null;

  final extension = filename.substring(dotIndex).toLowerCase();
  return _extensionToMimeType[extension];
}
