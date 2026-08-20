import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/life_runtime/domain/life_runtime_config.dart';
import 'package:lightly/features/life_runtime/infrastructure/life_runtime_file_config_codec.dart';

void main() {
  const codec = LifeRuntimeFileConfigCodec();
  const workspaceRoot =
      '/data/user/0/lightly.tool.plugin.liferuntime/files/runtime/workspaces';

  test('migrates the generated default project to the workspace root', () {
    final merged = codec.merge(const LifeRuntimeConfig(), <String, Object?>{
      'workspaceRoot': workspaceRoot,
      'mindgit': <String, Object?>{
        'server': <String, Object?>{'bind': '0.0.0.0', 'port': 9898},
        'projects': <Object?>[
          <String, Object?>{'path': '$workspaceRoot/default'},
        ],
      },
    });

    expect(merged.mindGit.workspace, './');
    expect(merged.mindGit.directories, const <String>['./']);
    expect(merged.mindGit.host, '0.0.0.0');
    expect(merged.mindGit.port, 9898);
  });

  test('loads Life Record paths and updates only the active AI profile', () {
    const host = LifeRuntimeConfig(
      lifeRecord: LifeRecordRuntimeConfig(
        ai: LifeRecordAiConfig(
          apiKey: 'old-active',
          activeProfileId: 'active',
          profiles: <LifeRecordAiProfile>[
            LifeRecordAiProfile(id: 'active', name: '当前', apiKey: 'old-active'),
            LifeRecordAiProfile(id: 'other', name: '其他', apiKey: 'keep-other'),
          ],
        ),
      ),
    );
    final merged = codec.merge(host, <String, Object?>{
      'workspaceRoot': workspaceRoot,
      'liferecordYaml':
          '''
title: 文件标题
root: '$workspaceRoot/summary'
host: 0.0.0.0
port: 9000
data_dir: '$workspaceRoot/life-record/data'
mode: public
comments: false
refresh: 5s
password_env: FILE_PASSWORD
exclude_dirs:
  - drafts
ai:
  enabled: true
  api_key: file-key
  base_url: https://file.example
  api_type: responses
  model: file-model
  thinking: false
  tools: false
  system_prompt: file prompt
''',
    });

    expect(merged.lifeRecord.root, 'summary');
    expect(merged.lifeRecord.dataDir, 'life-record/data');
    expect(merged.lifeRecord.port, 9000);
    expect(merged.lifeRecord.comments, isFalse);
    expect(merged.lifeRecord.ai.apiKey, 'file-key');
    expect(merged.lifeRecord.ai.profiles.first.apiKey, 'file-key');
    expect(merged.lifeRecord.ai.profiles.last.apiKey, 'keep-other');
  });
}
