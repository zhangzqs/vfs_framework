import 'dart:async';
import 'dart:convert';

enum Level { trace, debug, info, warning, error }

class Logger {
  Logger(
    StreamSink<LogRecord> sink, {
    this.level = defaultLevel,
    this.filenameEnabled = true,
    Map<String, Object> metadata = const {},
  }) : _sink = sink,
       _metadata = Map.unmodifiable(metadata);
  static const Level defaultLevel = Level.trace;
  static Logger defaultLogger = Logger(
    LogRecordConsoleAdapter(),
    level: defaultLevel,
  );
  final Level level;
  final Map<String, Object> _metadata;
  final StreamSink<LogRecord> _sink;
  final bool filenameEnabled;

  void log(
    Level level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
    String? filename,
  }) {
    if (level.index < this.level.index) return;

    // 如果启用了filename且没有提供filename，尝试从堆栈跟踪中获取
    String? actualFilename = filename;
    if (filenameEnabled && filename == null) {
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
    Map<String, Object>? metadata,
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
    Map<String, Object>? metadata,
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
    Map<String, Object>? metadata,
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
    Map<String, Object>? metadata,
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
    Map<String, Object>? metadata,
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
      filenameEnabled: filenameEnabled,
      metadata: {..._metadata, ...metadata},
    );
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
  final Map<String, Object>? metadata;
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

class LogRecordJsonAdapter implements StreamSink<LogRecord> {
  LogRecordJsonAdapter(this.originalSink);

  final StreamSink<String> originalSink;

  Map<String, dynamic> _recordToJson(LogRecord record) {
    return {
      'level': record.level.name,
      'message': record.message,
      'time': record.time.toIso8601String(),
      if (record.error != null) 'error': record.error?.toString(),
      if (record.stackTrace != null)
        'stackTrace': record.stackTrace?.toString(),
      if (record.filename != null) 'filename': record.filename,
      ...record.metadata ?? <String, Object>{},
    };
  }

  @override
  void add(LogRecord record) {
    originalSink.add(jsonEncode(_recordToJson(record)));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    originalSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<LogRecord> stream) {
    return stream.map(_recordToJson).map(jsonEncode).pipe(originalSink);
  }

  @override
  Future<void> close() => originalSink.close();

  @override
  Future<void> get done => originalSink.done;
}

class LogRecordConsoleAdapter implements StreamSink<LogRecord> {
  LogRecordConsoleAdapter();

  void _print(LogRecord record) {
    final buffer = StringBuffer()
      ..write('[${record.level.name.toUpperCase()}] ');

    // 添加时间戳（简化格式）
    final time = record.time;
    buffer.write(
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}',
    );

    // 添加文件名和行号
    if (record.filename != null) {
      buffer.write(' (${record.filename})');
    }

    buffer.write(': ${record.message}');

    // 如果有错误，添加错误信息
    if (record.error != null) {
      buffer.write(' | Error: ${record.error}');
    }

    // 如果有元数据，添加元数据信息
    if (record.metadata != null && record.metadata!.isNotEmpty) {
      buffer.write(' | ${record.metadata}');
    }

    print(buffer.toString());

    // 如果有堆栈跟踪，单独打印
    if (record.stackTrace != null) {
      print('StackTrace:\n${record.stackTrace}');
    }
  }

  @override
  void add(LogRecord record) {
    _print(record);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<LogRecord> stream) {
    return stream.forEach(_print);
  }

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();
}
