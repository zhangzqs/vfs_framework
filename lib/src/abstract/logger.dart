import 'dart:async';
import 'dart:convert';

enum Level { trace, debug, info, warning, error }

class Logger {
  Logger(
    StreamSink<LogRecord> sink, {
    this.level = defaultLevel,
    Map<String, Object> metadata = const {},
  }) : _sink = sink,
       _metadata = Map.unmodifiable(metadata);
  static const Level defaultLevel = Level.info;
  static Logger defaultLogger = Logger(
    LogRecordConsoleAdapter(),
    level: defaultLevel,
  );
  final Level level;
  final Map<String, Object> _metadata;
  final StreamSink<LogRecord> _sink;

  void log(
    Level level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) {
    if (level.index < this.level.index) return;

    final record = LogRecord(
      level,
      message,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );

    _sink.add(record);
  }

  void trace(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) => log(
    Level.trace,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
  void debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) => log(
    Level.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
  void info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) => log(
    Level.info,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) => log(
    Level.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? metadata,
  }) => log(
    Level.error,
    message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
  Logger withMetadata(Map<String, Object> metadata) {
    return Logger(_sink, level: level, metadata: {..._metadata, ...metadata});
  }
}

class LogRecord {
  LogRecord(
    this.level,
    this.message, {
    this.error,
    this.stackTrace,
    this.metadata,
  }) : time = DateTime.now();
  final Level level;
  final String message;
  final DateTime time;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object>? metadata;

  @override
  String toString() => '[${level.name}]: $message';
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
      ..write('[${record.level.name}] ')
      ..write(record.time.toIso8601String())
      ..write(' - ')
      ..write(record.message);
    if (record.error != null) {
      buffer.write(' | Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      buffer.write(' | StackTrace: ${record.stackTrace}');
    }
    if (record.metadata != null && record.metadata!.isNotEmpty) {
      buffer.write(' | Metadata: ${record.metadata}');
    }
    print(buffer.toString());
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
