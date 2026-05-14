import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

class BrowserFindController {
  BrowserFindController();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  FindInteractionController? _interactionController;
  int _currentMatch = 0;
  int _matchCount = 0;

  FindInteractionController? get interactionController =>
      _interactionController;
  bool get isAvailable => _interactionController != null;
  int get currentMatch => _currentMatch;
  int get matchCount => _matchCount;

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

  void clearMatches() {
    _interactionController?.clearMatches();
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
    await _interactionController?.findAll(find: trimmed);
  }

  Future<void> findNext({required bool forward}) async {
    await _interactionController?.findNext(forward: forward);
  }

  void dispose() {
    revision.dispose();
    _interactionController?.dispose();
  }
}
