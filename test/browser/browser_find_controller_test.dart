import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_find_controller.dart';

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
  });
}
