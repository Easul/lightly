import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserFindController {
  BrowserFindController({FindInteractionController? interactionController})
    : _interactionController = interactionController;

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
    if (_interactionController != null) {
      return;
    }
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
    final interactionController = _interactionController;
    if (interactionController == null) {
      return;
    }
    await interactionController.findAll(find: trimmed);
    await refreshActiveSession();
  }

  Future<void> findNext({required bool forward}) async {
    await _interactionController?.findNext(forward: forward);
    await refreshActiveSession();
  }

  Future<void> refreshActiveSession() async {
    final session = await _interactionController?.getActiveFindSession();
    if (session == null) {
      return;
    }
    _currentMatch = session.highlightedResultIndex < 0
        ? 0
        : session.highlightedResultIndex;
    _matchCount = session.resultCount;
    revision.value++;
  }

  void dispose() {
    revision.dispose();
    _interactionController?.dispose();
  }
}
