import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/life_runtime/domain/life_runtime_config.dart';

void main() {
  test('uses workspace-oriented runtime defaults', () {
    const config = LifeRuntimeConfig();

    expect(config.mindGit.directories, const <String>['./']);
    expect(config.lifeRecord.root, 'summary');
    expect(config.lifeRecord.port, 8347);
    expect(config.lifeRecord.dataDir, 'life-record/data');
    expect(config.lifeRecord.baseUrl, isEmpty);
  });

  test('migrates legacy AI fields into a default profile', () {
    final config = LifeRuntimeConfig.fromJson(<String, Object?>{
      'mindgit': <String, Object?>{
        'workspace': 'default',
        'directories': <String>['default'],
      },
      'liferecord': <String, Object?>{
        'root': 'temp/summary',
        'port': 8080,
        'baseUrl': 'http://127.0.0.1:8080',
        'passwordEnv': 'LIFERECORD_PASSWORD',
        'ai': <String, Object?>{
          'apiKey': 'legacy-key',
          'baseUrl': 'https://legacy.example',
          'apiType': 'responses',
          'model': 'legacy-model',
        },
      },
    });

    expect(config.mindGit.directories, const <String>['./']);
    expect(config.lifeRecord.ai.activeProfileId, 'default');
    expect(config.lifeRecord.root, 'summary');
    expect(config.lifeRecord.port, 8347);
    expect(config.lifeRecord.baseUrl, isEmpty);
    expect(config.lifeRecord.passwordEnv, isEmpty);
    expect(config.lifeRecord.ai.profiles.single.apiKey, 'legacy-key');
    expect(config.lifeRecord.ai.baseUrl, 'https://legacy.example');
  });

  test('round-trips the selected AI upstream profile', () {
    const config = LifeRuntimeConfig(
      lifeRecord: LifeRecordRuntimeConfig(
        ai: LifeRecordAiConfig(
          apiKey: 'key-b',
          baseUrl: 'https://b.example',
          apiType: 'responses',
          model: 'model-b',
          activeProfileId: 'b',
          profiles: <LifeRecordAiProfile>[
            LifeRecordAiProfile(id: 'a', name: '上游 A'),
            LifeRecordAiProfile(
              id: 'b',
              name: '上游 B',
              apiKey: 'key-b',
              baseUrl: 'https://b.example',
              apiType: 'responses',
              model: 'model-b',
            ),
          ],
        ),
      ),
    );

    final restored = LifeRuntimeConfig.decode(config.encode());

    expect(restored.lifeRecord.ai.activeProfileId, 'b');
    expect(restored.lifeRecord.ai.profiles, hasLength(2));
    expect(restored.lifeRecord.ai.apiKey, 'key-b');
    expect(restored.lifeRecord.ai.model, 'model-b');
  });

  test('preserves explicit legacy-looking values after schema migration', () {
    final config = LifeRuntimeConfig.fromJson(<String, Object?>{
      'version': 2,
      'liferecord': <String, Object?>{
        'root': 'temp/summary',
        'port': 8080,
        'baseUrl': 'http://127.0.0.1:8080',
        'passwordEnv': 'LIFERECORD_PASSWORD',
      },
    });

    expect(config.lifeRecord.root, 'temp/summary');
    expect(config.lifeRecord.port, 8080);
    expect(config.lifeRecord.baseUrl, 'http://127.0.0.1:8080');
    expect(config.lifeRecord.passwordEnv, 'LIFERECORD_PASSWORD');
  });
}
