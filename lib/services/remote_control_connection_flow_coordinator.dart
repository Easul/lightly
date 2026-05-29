import 'dart:async';

typedef RemoteControlConnectionAttempt =
    Future<void> Function(int attempt, void Function() markNativeStarted);
typedef RemoteControlConnectionPrepareAttempt = void Function(int attempt);
typedef RemoteControlConnectionReset =
    Future<void> Function({required bool stopNative});
typedef RemoteControlConnectionDelay = Future<void> Function(Duration duration);
typedef RemoteControlConnectionLog =
    void Function(String message, {Object? error});

class RemoteControlConnectionFlowCoordinator {
  RemoteControlConnectionFlowCoordinator({
    this.maxAttempts = 4,
    this.readyTimeout = const Duration(seconds: 2),
    RemoteControlConnectionDelay? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final int maxAttempts;
  final Duration readyTimeout;
  final RemoteControlConnectionDelay _delay;
  Completer<void>? _readyCompleter;

  void markReady() {
    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> connect({
    required RemoteControlConnectionPrepareAttempt prepareAttempt,
    required RemoteControlConnectionAttempt attemptConnection,
    required RemoteControlConnectionReset resetConnection,
    RemoteControlConnectionLog? log,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      var nativeControllerStarted = false;
      try {
        _readyCompleter = Completer<void>();
        prepareAttempt(attempt);

        await attemptConnection(attempt, () {
          nativeControllerStarted = true;
        });
        await _readyCompleter!.future.timeout(readyTimeout);
        return;
      } catch (error) {
        lastError = error;
        log?.call(
          'Connect attempt ${attempt + 1} failed: $error',
          error: error,
        );
        await resetConnection(stopNative: nativeControllerStarted);
        if (attempt < maxAttempts - 1) {
          await _delay(retryDelayForAttempt(attempt));
        }
      } finally {
        _readyCompleter = null;
      }
    }

    throw lastError ?? Exception('连接失败');
  }

  Duration retryDelayForAttempt(int attempt) {
    return Duration(milliseconds: 350 * (attempt + 1));
  }
}
