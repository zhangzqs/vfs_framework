import 'dart:async';

import 'log_record_adapter.dart';
import 'text_sink.dart';

enum Level { trace, debug, info, warning, error }

class Logger {
  Logger(
    StreamSink<LogRecord> sink, {
    this.level = defaultLevel,
    this.sourceFilenameEnabled = true,
    Map<String, dynamic> metadata = const {},
  }) : _sink = sink,
       _metadata = Map.unmodifiable(metadata);
  static const Level defaultLevel = Level.info;

  static final Logger defaultLogger = Logger(
    LogRecordTextAdapter(TextConsoleSink()),
    level: Logger.defaultLevel,
    sourceFilenameEnabled: true,
  );

  final Level level;
  final Map<String, dynamic> _metadata;
  final StreamSink<LogRecord> _sink;
  final bool sourceFilenameEnabled;

  void log(
    Level level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) {
    if (level.index < this.level.index) return;

    // 如果启用了filename且没有提供filename，尝试从堆栈跟踪中获取
    String? actualFilename = filename;
    if (sourceFilenameEnabled && filename == null) {
      actualFilename = _extractFilenameFromStackTrace();
    }

    final record = LogRecord(
      level,
      message,
      error: error,
      stackTrace: stackTrace,
      metadata: {..._metadata, if (metadata != null) ...metadata},
      filename: actualFilename,
    );

    _sink.add(record);
  }

  /// 从堆栈跟踪中提取文件名和行号
  String? _extractFilenameFromStackTrace() {
    try {
      final stackTrace = StackTrace.current;
      final lines = stackTrace.toString().split('\n');

      // 寻找第一个不是Logger内部方法的调用
      for (final line in lines) {
        if (line.contains('.dart') &&
            !line.contains('logger.dart') &&
            !line.contains('Logger.')) {
          // 提取文件名和行号，格式通常是: #1      method (file:///path/to/file.dart:line:column)
          final match = RegExp(r'([^/\\]+\.dart):(\d+):(\d+)').firstMatch(line);
          if (match != null) {
            final filename = match.group(1);
            final lineNumber = match.group(2);
            return '$filename:$lineNumber';
          }

          // 备用匹配模式，只有文件名没有行号的情况
          final filenameMatch = RegExp(r'([^/\\]+\.dart)').firstMatch(line);
          if (filenameMatch != null) {
            return filenameMatch.group(1);
          }
        }
      }
    } catch (e) {
      // 如果提取失败，忽略错误
    }
    return null;
  }

  void trace(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) => log(
    Level.trace,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    filename: filename,
  );

  void debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) => log(
    Level.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    filename: filename,
  );

  void info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) => log(
    Level.info,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    filename: filename,
  );

  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) => log(
    Level.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    filename: filename,
  );

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? filename,
  }) => log(
    Level.error,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    filename: filename,
  );
  Logger withMetadata(Map<String, Object> metadata) {
    return Logger(
      _sink,
      level: level,
      sourceFilenameEnabled: sourceFilenameEnabled,
      metadata: {..._metadata, ...metadata},
    );
  }

  Future<void> close() async {
    await _sink.close();
  }
}

class LogRecord {
  LogRecord(
    this.level,
    this.message, {
    this.error,
    this.stackTrace,
    this.metadata,
    this.filename,
  }) : time = DateTime.now();
  final Level level;
  final String message;
  final DateTime time;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final String? filename;

  @override
  String toString() {
    final buffer = StringBuffer()..write('[${level.name.toUpperCase()}]');

    if (filename != null) {
      buffer.write(' ($filename)');
    }

    buffer.write(': $message');

    return buffer.toString();
  }
}
