import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserFindController {
  BrowserFindController();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  FindInteractionController? _interactionController;
  InAppWebViewController? _webViewController;
  int _currentMatch = 0;
  int _matchCount = 0;

  FindInteractionController? get interactionController =>
      _interactionController;
  bool get isAvailable => _interactionController != null;
  int get currentMatch => _currentMatch;
  int get matchCount => _matchCount;

  void attachWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
  }

  void initialize() {
    if (InAppWebViewPlatform.instance == null) {
      return;
    }
    _interactionController = FindInteractionController(
      onFindResultReceived:
          (controller, activeMatchOrdinal, numberOfMatches, isDoneCounting) {
            _currentMatch = activeMatchOrdinal;
            _matchCount = numberOfMatches;
            revision.value++;
          },
    );
  }

  void notifyQueryChanged() {
    revision.value++;
  }

  Future<void> clearMatches() async {
    final controller = _webViewController;
    if (controller != null) {
      // ignore: deprecated_member_use
      await controller.clearMatches();
      return;
    }
    await _interactionController?.clearMatches();
  }

  void resetResults() {
    _currentMatch = 0;
    _matchCount = 0;
    revision.value++;
  }

  Future<void> findAll(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return;
    }
    resetResults();
    final controller = _webViewController;
    if (controller != null) {
      // ignore: deprecated_member_use
      await controller.findAllAsync(find: trimmed);
      return;
    }
    await _interactionController?.findAll(find: trimmed);
  }

  Future<void> findNext({required bool forward}) async {
    final controller = _webViewController;
    if (controller != null) {
      // ignore: deprecated_member_use
      await controller.findNext(forward: forward);
      return;
    }
    await _interactionController?.findNext(forward: forward);
  }

  void dispose() {
    revision.dispose();
    _interactionController?.dispose();
  }
}
