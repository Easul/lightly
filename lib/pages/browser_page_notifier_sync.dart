import 'package:flutter/foundation.dart';

class BrowserPageNotifierSync {
  const BrowserPageNotifierSync();

  void sync({
    required ValueNotifier<bool> isLoadingNotifier,
    required bool isLoading,
    required ValueNotifier<bool> canGoBackNotifier,
    required bool canGoBack,
    required ValueNotifier<bool> canGoForwardNotifier,
    required bool canGoForward,
    required ValueNotifier<bool> isSecureNotifier,
    required bool isSecure,
    required ValueNotifier<int> tabCountNotifier,
    required int tabCount,
    required ValueNotifier<String> statusMessageNotifier,
    required String statusMessage,
  }) {
    _setIfChanged(isLoadingNotifier, isLoading);
    _setIfChanged(canGoBackNotifier, canGoBack);
    _setIfChanged(canGoForwardNotifier, canGoForward);
    _setIfChanged(isSecureNotifier, isSecure);
    _setIfChanged(tabCountNotifier, tabCount);
    _setIfChanged(statusMessageNotifier, statusMessage);
  }

  void resetProgress({
    required ValueNotifier<int> progressNotifier,
    required void Function(int value) setProgress,
  }) {
    setProgress(0);
    progressNotifier.value = 0;
  }

  void _setIfChanged<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value != value) {
      notifier.value = value;
    }
  }
}
