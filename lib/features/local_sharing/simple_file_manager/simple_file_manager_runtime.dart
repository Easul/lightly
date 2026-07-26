import 'simple_file_manager_settings.dart';

abstract class SimpleFileManagerRuntime {
  Future<SimpleFileManagerSettings> loadSettings();

  Future<void> applySettings(SimpleFileManagerSettings settings);

  Future<void> start({SimpleFileManagerSettings? settings});

  Future<void> stop();
}
