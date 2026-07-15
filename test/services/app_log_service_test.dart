import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('re-enabling logging clears the previous log session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('app-log-test-');
    final logFile = File('${directory.path}/runtime.log');
    await logFile.writeAsString('previous session\n');
    final service = AppLogService.forTesting(logFile: logFile, enabled: true);

    try {
      await service.log('old event');
      await service.setEnabled(false);
      expect(await logFile.exists(), isFalse);
      await service.setEnabled(true);
      await service.log('new event');

      final contents = await service.readLogContents();
      expect(contents, isNot(contains('previous session')));
      expect(contents, isNot(contains('old event')));
      expect(contents, contains('Runtime logging enabled'));
      expect(contents, contains('new event'));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
