import 'package:flutter/material.dart';

import '../features/tools/tool_visibility_store.dart';

class ToolVisibilitySettingsPage extends StatefulWidget {
  const ToolVisibilitySettingsPage({super.key});

  @override
  State<ToolVisibilitySettingsPage> createState() =>
      _ToolVisibilitySettingsPageState();
}

class _ToolVisibilitySettingsPageState
    extends State<ToolVisibilitySettingsPage> {
  final ToolVisibilityStore _store = ToolVisibilityStore();
  Set<String>? _hiddenIds;

  static const _tools = <({String id, String label, IconData icon})>[
    (id: ToolVisibilityStore.tg, label: 'TG 工具', icon: Icons.telegram),
    (
      id: ToolVisibilityStore.chat,
      label: '聊天工具',
      icon: Icons.chat_bubble_outline_rounded,
    ),
    (
      id: ToolVisibilityStore.remoteControl,
      label: '远程控制',
      icon: Icons.control_camera_rounded,
    ),
    (
      id: ToolVisibilityStore.p2pVpn,
      label: 'P2P VPN',
      icon: Icons.vpn_lock_rounded,
    ),
    (
      id: ToolVisibilityStore.lifeRuntime,
      label: '人生运行时',
      icon: Icons.auto_stories_rounded,
    ),
    (
      id: ToolVisibilityStore.calculator,
      label: '计算器',
      icon: Icons.calculate_rounded,
    ),
    (
      id: ToolVisibilityStore.translation,
      label: '翻译工具',
      icon: Icons.translate_rounded,
    ),
    (
      id: ToolVisibilityStore.music,
      label: '音乐',
      icon: Icons.library_music_rounded,
    ),
    (
      id: ToolVisibilityStore.game2048,
      label: '2048',
      icon: Icons.grid_view_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hidden = await _store.loadHiddenIds();
    if (mounted) setState(() => _hiddenIds = hidden);
  }

  Future<void> _setVisible(String id, bool visible) async {
    final next = {...?_hiddenIds};
    if (visible) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _hiddenIds = next);
    await _store.saveHiddenIds(next);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _hiddenIds;
    return Scaffold(
      appBar: AppBar(title: const Text('工具显示设置')),
      body: hidden == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('选择要在“小工具”中显示的功能'),
                ),
                ..._tools.map(
                  (tool) => SwitchListTile(
                    secondary: Icon(tool.icon),
                    title: Text(tool.label),
                    value: !hidden.contains(tool.id),
                    onChanged: (value) => _setVisible(tool.id, value),
                  ),
                ),
              ],
            ),
    );
  }
}
