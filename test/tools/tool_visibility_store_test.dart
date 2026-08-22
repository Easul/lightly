import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/features/tools/tool_visibility_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hides the selected tools by default', () async {
    final hidden = await ToolVisibilityStore().loadHiddenIds();
    expect(hidden, ToolVisibilityStore.hiddenByDefault);
  });

  test('round trips the selected hidden ids', () async {
    final store = ToolVisibilityStore();
    await store.saveHiddenIds([
      ToolVisibilityStore.music,
      ToolVisibilityStore.tg,
    ]);
    expect(await store.loadHiddenIds(), {
      ToolVisibilityStore.music,
      ToolVisibilityStore.tg,
    });
  });
}
