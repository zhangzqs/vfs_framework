import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

final class Path extends Equatable {
  factory Path.fromString(String path) {
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
    return Path._internal(cleanedParts);
  }
  Path._internal(this.segments) {
    for (final segment in segments) {
      if (segment.contains('/')) {
        throw ArgumentError('Path segments cannot contain "/"');
      }
      if (segment.contains('\\')) {
        throw ArgumentError('Path segments cannot contain "\\"');
      }
      if (segment == '' || segment == '.' || segment == '..') {
        throw ArgumentError('Path segments cannot be empty, ".", or ".."');
      }
    }
  }
  static final rootPath = Path._internal([]);

  final List<String> segments;

  /// 获取路径的文件名
  String? get filename {
    if (segments.isEmpty) return null;
    return segments.last;
  }

  /// 拼接路径
  Path join(String segment) {
    return joinAll([segment]);
  }

  Path joinAll(Iterable<String> segments) {
    if (segments.isEmpty) return this;
    return Path._internal([
      ...this.segments,
      ...segments.where((s) => s.isNotEmpty),
    ]);
  }

  /// 获取路径的父目录
  Path? get parent {
    if (segments.isEmpty) return null;
    return Path._internal(segments.sublist(0, segments.length - 1));
  }

  bool get isRoot => segments.isEmpty;

  @override
  String toString() {
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  @override
  List<Object?> get props => [segments];
}

class PathJsonConverter implements JsonConverter<Path, String> {
  const PathJsonConverter();

  @override
  Path fromJson(String json) {
    return Path.fromString(json);
  }

  @override
  String toJson(Path path) {
    return path.toString();
  }
}
