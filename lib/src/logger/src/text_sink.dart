import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TextConsoleSink implements StreamSink<String> {
  TextConsoleSink();

  @override
  void add(String data) {
    print(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    print('Error: $error');
    if (stackTrace != null) {
      print('StackTrace: $stackTrace');
    }
  }

  @override
  Future<void> addStream(Stream<String> stream) {
    return stream.forEach(print);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();
}

class TextFileSink implements StreamSink<String> {
  TextFileSink(
    this.directory, {
    this.maxFileSize = 512 * 1024 * 1024, // 默认512MB
    this.maxFiles = 5, // 最多保留5个文件
  });

  final Directory directory;
  final int maxFileSize; // 单个文件最大大小（字节）
  final int maxFiles; // 最多保留的文件数量
  IOSink? _sink;
  String? _currentFileName;
  int _currentFileSize = 0;

  /// 生成日志文件名，格式为: 20250803-123526.log
  String _generateFileName() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '.log';
  }

  /// 创建新的日志文件
  Future<void> _createNewFile() async {
    await _sink?.close();

    _currentFileName = _generateFileName();
    final file = File('${directory.path}/$_currentFileName');

    // 确保目录存在
    await directory.create(recursive: true);

    _sink = file.openWrite(mode: FileMode.append);
    _currentFileSize = 0;

    // 清理旧文件
    await _cleanupOldFiles();
  }

  /// 清理超出数量限制的旧文件
  Future<void> _cleanupOldFiles() async {
    try {
      final files = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // 按修改时间排序，最新的在前
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

      // 删除超出限制的文件
      if (files.length > maxFiles) {
        for (int i = maxFiles; i < files.length; i++) {
          try {
            await files[i].delete();
          } catch (e) {
            // 忽略删除失败的错误
          }
        }
      }
    } catch (e) {
      // 忽略清理过程中的错误
    }
  }

  /// 检查是否需要轮转文件
  Future<void> _checkRotation(String data) async {
    final dataSize = utf8.encode(data).length;

    if (_sink == null || _currentFileSize + dataSize > maxFileSize) {
      await _createNewFile();
    }

    _currentFileSize += dataSize;
  }

  @override
  void add(String data) {
    _checkRotation(data)
        .then((_) {
          _sink?.writeln(data);
        })
        .catchError((Object e) {
          // 如果写入失败，尝试输出到控制台
          print('Failed to write to log file: $e');
          print(data);
        });
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    final errorMessage = 'ERROR: $error';
    final stackMessage = stackTrace != null ? 'STACK: $stackTrace' : '';

    add(errorMessage);
    if (stackMessage.isNotEmpty) {
      add(stackMessage);
    }
  }

  @override
  Future<void> addStream(Stream<String> stream) {
    return stream.forEach(add);
  }

  @override
  Future<void> close() async {
    await _sink?.close();
    _sink = null;
  }

  @override
  Future<void> get done => _sink?.done ?? Future.value();
}
