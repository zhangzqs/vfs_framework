import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'path.dart';

part 'status.g.dart';

@JsonSerializable()
final class FileStatus extends Equatable {
  const FileStatus({
    required this.isDirectory,
    required this.path,
    this.size,
    this.mimeType,
  });
  factory FileStatus.fromJson(Map<String, dynamic> json) =>
      _$FileStatusFromJson(json);

  @PathJsonConverter()
  final Path path;
  final int? size;
  final bool isDirectory;
  final String? mimeType;

  @override
  List<Object?> get props => [path, size, isDirectory, mimeType];

  Map<String, dynamic> toJson() => _$FileStatusToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
