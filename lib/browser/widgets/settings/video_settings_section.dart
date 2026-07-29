import 'package:flutter/material.dart';

import 'settings_section_widgets.dart';

class VideoSettingsSection extends StatelessWidget {
  const VideoSettingsSection({
    super.key,
    required this.nativeVideoPlayerEnabled,
    required this.onNativeVideoPlayerEnabledChanged,
  });

  final bool nativeVideoPlayerEnabled;
  final ValueChanged<bool> onNativeVideoPlayerEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: nativeVideoPlayerEnabled,
          title: const Text('原生视频播放器'),
          subtitle: const Text('检测 YouTube 视频并使用原生播放器播放'),
          onChanged: onNativeVideoPlayerEnabledChanged,
        ),
      ],
    );
  }
}
