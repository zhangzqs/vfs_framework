/// Represents a WebDAV file or directory entry.
///
/// This class contains metadata about a file or directory in the WebDAV
/// server, including its path, type, size, timestamps, and other properties.
class File {
  /// Creates a new File instance with the specified properties.
  ///
  /// [path] - The full path to the file or directory
  /// [isDir] - Whether this entry is a directory
  /// [name] - The name of the file or directory
  /// [mimeType] - The MIME type of the file
  /// [size] - The size of the file in bytes
  /// [eTag] - The entity tag for caching
  /// [cTime] - The creation timestamp
  /// [mTime] - The last modification timestamp
  File({
    this.path,
    this.isDir,
    this.name,
    this.mimeType,
    this.size,
    this.eTag,
    this.cTime,
    this.mTime,
  });

  /// The full path to the file or directory.
  String? path;

  /// Whether this entry is a directory.
  bool? isDir;

  /// The name of the file or directory.
  String? name;

  /// The MIME type of the file.
  String? mimeType;

  /// The size of the file in bytes.
  int? size;

  /// The entity tag for caching purposes.
  String? eTag;

  /// The creation timestamp.
  DateTime? cTime;

  /// The last modification timestamp.
  DateTime? mTime;
}
