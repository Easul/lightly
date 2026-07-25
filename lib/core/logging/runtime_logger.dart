import 'package:flutter/foundation.dart';

/// Cross-feature sink for bounded, sanitized runtime diagnostics.
abstract class RuntimeLogger {
  Future<void> initialize();

  Future<void> log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  });

  Future<void> logFlutterError(FlutterErrorDetails details);

  Future<void> logUnhandledError(Object error, StackTrace stackTrace);
}
