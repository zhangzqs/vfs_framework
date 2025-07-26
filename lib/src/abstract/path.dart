import 'package:equatable/equatable.dart';

final class Path extends Equatable {

  Path(this.segments) {
    // 禁止出现.和..
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      throw ArgumentError('Path segments cannot contain "." or ".."');
    }
  }
  static final rootPath = Path([]);

  final List<String> segments;

  static Path fromString(String path) {
    // 自动处理.和..，并去除多余的斜杠
    List<String> parts = path.split('/');
    List<String> cleanedParts = [];
    for (final String part in parts) {
      if (part == '.' || part.isEmpty) {
        continue; // 忽略当前目录和多余的斜杠
      } else if (part == '..') {
        if (cleanedParts.isNotEmpty) {
          cleanedParts.removeLast(); // 返回上一级目录
        }
      } else {
        cleanedParts.add(part); // 添加有效部分
      }
    }
    return Path(cleanedParts);
  }

  /// 获取路径的文件名
  String? get filename {
    if (segments.isEmpty) return null;
    return segments.last;
  }

  /// 拼接路径
  Path join(String segment) {
    if (segment.isEmpty) return this;
    return Path([...segments, segment]);
  }

  /// 获取路径的父目录
  Path? get parent {
    if (segments.isEmpty) return null;
    return Path(segments.sublist(0, segments.length - 1));
  }

  bool get isRoot => segments.isEmpty;

  @override
  String toString() {
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  @override
  List<Object?> get props => [segments];
}
