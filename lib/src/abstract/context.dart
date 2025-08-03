import 'dart:async';

import 'package:uuid/uuid.dart';

import '../logger/index.dart';
import 'errors.dart';

class Context {
  Context({Logger? logger, String? operationID})
    : logger = logger ?? defaultLogger,
      _operationID = operationID ?? const Uuid().v8();

  String get operationID => _operationID;
  final String _operationID;

  bool get isCanceled => _cancelError != null;
  FileSystemException? get cancelError => _cancelError;
  FileSystemException? _cancelError;

  final Completer<FileSystemException> _completer =
      Completer<FileSystemException>();
  Future<FileSystemException> get whenCancel => _completer.future;
  void cancel([Object? reason]) {
    _cancelError = FileSystemException(
      code: FileSystemErrorCode.contextCanceled,
      message: reason?.toString() ?? 'Operation canceled',
    );
    if (!_completer.isCompleted) {
      _completer.complete(_cancelError);
    }
  }

  static Logger defaultLogger = Logger.defaultLogger;
  Logger logger;
}
