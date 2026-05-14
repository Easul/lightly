import 'package:flutter/material.dart';

import 'settings_section_widgets.dart';

class VideoSettingsSection extends StatelessWidget {
  const VideoSettingsSection({
    super.key,
    required this.nativeVideoPlayerEnabled,
    required this.nativeVideoParserApiController,
    required this.onNativeVideoPlayerEnabledChanged,
    required this.onParserApiChanged,
  });

  final bool nativeVideoPlayerEnabled;
  final TextEditingController nativeVideoParserApiController;
  final ValueChanged<bool> onNativeVideoPlayerEnabledChanged;
  final ValueChanged<String> onParserApiChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: nativeVideoPlayerEnabled,
          title: const Text('原生视频播放器'),
          subtitle: const Text('检测视频并使用全屏原生播放器播放'),
          onChanged: onNativeVideoPlayerEnabledChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nativeVideoParserApiController,
          decoration: const InputDecoration(
            labelText: 'YouTube 解析接口',
            hintText: 'https://parser.example.com',
            prefixIcon: Icon(Icons.api_outlined),
            helperText: '留空时不进行 YouTube 悬浮窗/原生播放器解析',
          ),
          keyboardType: TextInputType.url,
          onChanged: onParserApiChanged,
        ),
      ],
    );
  }
}
