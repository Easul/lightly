import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_webview_state_reader.dart';

void main() {
  group('BrowserWebViewStateReader', () {
    const reader = BrowserWebViewStateReader();

    test('reads navigation state sequentially while available', () async {
      final events = <String>[];

      final snapshot = await reader.readNavigationSnapshot(
        isAvailable: () => true,
        readCanGoBack: () async {
          events.add('back');
          return true;
        },
        readCanGoForward: () async {
          events.add('forward');
          return false;
        },
      );

      expect(events, <String>['back', 'forward']);
      expect(snapshot?.canGoBack, isTrue);
      expect(snapshot?.canGoForward, isFalse);
    });

    test('skips navigation reads when WebView is unavailable', () async {
      var readCount = 0;

      final snapshot = await reader.readNavigationSnapshot(
        isAvailable: () => false,
        readCanGoBack: () async {
          readCount += 1;
          return true;
        },
        readCanGoForward: () async {
          readCount += 1;
          return true;
        },
      );

      expect(snapshot, isNull);
      expect(readCount, 0);
    });

    test('waits before reading the load snapshot in parallel', () async {
      final events = <String>[];

      final snapshot = await reader.readLoadSnapshot(
        isAvailable: () => true,
        readTitle: () async {
          events.add('title');
          return 'Example';
        },
        readCanGoBack: () async {
          events.add('back');
          return true;
        },
        readCanGoForward: () async {
          events.add('forward');
          return false;
        },
        wait: (duration) async {
          expect(duration, const Duration(milliseconds: 200));
          events.add('wait');
        },
      );

      expect(events.first, 'wait');
      expect(events.skip(1), containsAll(<String>['title', 'back', 'forward']));
      expect(snapshot?.title, 'Example');
      expect(snapshot?.canGoBack, isTrue);
      expect(snapshot?.canGoForward, isFalse);
    });

    test('drops a snapshot when WebView detaches during reads', () async {
      var available = true;
      final readsStarted = Completer<void>();
      final titleCompleter = Completer<String?>();

      final snapshotFuture = reader.readLoadSnapshot(
        isAvailable: () => available,
        readTitle: () {
          readsStarted.complete();
          return titleCompleter.future;
        },
        readCanGoBack: () async => true,
        readCanGoForward: () async => true,
        wait: (_) async {},
      );
      await readsStarted.future;
      available = false;
      titleCompleter.complete('Detached');

      expect(await snapshotFuture, isNull);
    });
  });
}
