import 'dart:async';
import 'dart:convert';

import 'logger.dart';

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

class LogRecordTextAdapter implements StreamSink<LogRecord> {
  LogRecordTextAdapter(this.originalSink);

  final StreamSink<String> originalSink;

  String _recordToText(LogRecord record) {
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

    // 如果有堆栈跟踪，单独打印
    if (record.stackTrace != null) {
      buffer.write('StackTrace:\n${record.stackTrace}');
    }
    return buffer.toString();
  }

  @override
  void add(LogRecord record) {
    final text = _recordToText(record);
    originalSink.add(text);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    originalSink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<LogRecord> stream) {
    return stream.map(_recordToText).pipe(originalSink);
  }

  @override
  Future<void> close() => originalSink.close();

  @override
  Future<void> get done => originalSink.done;
}
