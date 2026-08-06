import 'simple_file_manager_settings.dart';

abstract class SimpleFileManagerSettingsStore {
  Future<SimpleFileManagerSettings> loadSettings();

  Future<void> saveSettings(SimpleFileManagerSettings settings);
}
