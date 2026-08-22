import 'package:flutter_test/flutter_test.dart';

import '../../lib/pages/browser_page_input_resolver.dart';

void main() {
  test('recognizes the local developer tools command', () {
    expect(
      BrowserPageInputResolver.isDeveloperToolsCommand('  lightly://DEVTOOLS '),
      isTrue,
    );
    expect(
      BrowserPageInputResolver.isDeveloperToolsCommand('lightly://other'),
      isFalse,
    );
  });
}
