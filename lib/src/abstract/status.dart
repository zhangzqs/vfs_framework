import 'package:equatable/equatable.dart';
import 'path.dart';

final class FileStatus extends Equatable {
  const FileStatus({
    required this.isDirectory,
    required this.path,
    this.size,
    this.mimeType,
  });

  final Path path;
  final int? size;
  final bool isDirectory;
  final String? mimeType;

  @override
  List<Object?> get props => [path, size, isDirectory, mimeType];
}
