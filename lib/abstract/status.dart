import 'package:equatable/equatable.dart';
import 'path.dart';

final class FileStatus extends Equatable {
  final Path path;
  final int? size;
  final bool isDirectory;

  const FileStatus({required this.isDirectory, required this.path, this.size});

  @override
  List<Object?> get props => [path, size, isDirectory];
}
