import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_find_controller.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  group('BrowserFindController', () {
    late BrowserFindController controller;

    setUp(() {
      controller = BrowserFindController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts unavailable until initialized', () {
      expect(controller.isAvailable, isFalse);
      expect(controller.interactionController, isNull);
      expect(controller.currentMatch, 0);
      expect(controller.matchCount, 0);
    });

    test('initialize stays safe without a platform implementation', () {
      controller.initialize();

      expect(controller.isAvailable, isFalse);
      expect(controller.interactionController, isNull);
    });

    test('resetResults clears match state and bumps revision', () {
      final before = controller.revision.value;

      controller.resetResults();

      expect(controller.currentMatch, 0);
      expect(controller.matchCount, 0);
      expect(controller.revision.value, before + 1);
    });

    test('findAll ignores empty keywords', () async {
      final before = controller.revision.value;

      await controller.findAll('   ');

      expect(controller.revision.value, before);
    });

    test('notifyQueryChanged bumps revision', () {
      final before = controller.revision.value;

      controller.notifyQueryChanged();

      expect(controller.revision.value, before + 1);
    });

    test('uses find interaction controller for search operations', () async {
      final interactionController = _FakeFindInteractionController();
      controller.dispose();
      controller = BrowserFindController(
        interactionController: interactionController,
      );

      await controller.findAll(' keyword ');
      await controller.findNext(forward: false);
      await controller.clearMatches();

      expect(interactionController.lastFindText, 'keyword');
      expect(interactionController.lastFindForward, isFalse);
      expect(interactionController.clearMatchCalls, 1);
      expect(controller.currentMatch, 1);
      expect(controller.matchCount, 3);
    });
  });
}

class _FakeFindInteractionController extends Fake
    implements FindInteractionController {
  String? lastFindText;
  bool? lastFindForward;
  int clearMatchCalls = 0;

  @override
  Future<void> findAll({String? find}) async {
    lastFindText = find;
  }

  @override
  Future<void> findNext({bool forward = true}) async {
    lastFindForward = forward;
  }

  @override
  Future<void> clearMatches() async {
    clearMatchCalls++;
  }

  @override
  Future<FindSession?> getActiveFindSession() async {
    return FindSession(
      highlightedResultIndex: 1,
      resultCount: 3,
      searchResultDisplayStyle: SearchResultDisplayStyle.CURRENT_AND_TOTAL,
    );
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}
