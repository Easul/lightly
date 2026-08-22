import 'dart:async';

import 'package:flutter/material.dart';

import '../features/optional_plugins/domain/optional_feature.dart';
import '../features/optional_plugins/presentation/optional_feature_gate.dart';
import '../features/tools/tool_visibility_store.dart';
import '../services/app_toast.dart';
import '../services/time_overlay_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> with WidgetsBindingObserver {
  final TimeOverlayService _timeOverlayService = TimeOverlayService();
  final OptionalFeatureGate _optionalFeatureGate = OptionalFeatureGate();
  final ToolVisibilityStore _toolVisibilityStore = ToolVisibilityStore();
  bool _timeOverlayRunning = false;
  bool _busy = false;
  Set<String>? _hiddenToolIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshOverlayState());
    unawaited(_refreshToolVisibility());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOverlayState());
      unawaited(_refreshToolVisibility());
    }
  }

  Future<void> _refreshToolVisibility() async {
    final hidden = await _toolVisibilityStore.loadHiddenIds();
    if (mounted) setState(() => _hiddenToolIds = hidden);
  }

  bool _visible(String id) => !(_hiddenToolIds ?? {}).contains(id);

  Future<void> _refreshOverlayState() async {
    try {
      final running = await _timeOverlayService.isRunning();
      if (mounted && running != _timeOverlayRunning) {
        setState(() => _timeOverlayRunning = running);
      }
    } catch (error) {
      debugPrint('Refresh time overlay state failed: $error');
    }
  }

  Future<void> _toggleTimeOverlay(bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled) {
        if (!await _timeOverlayService.hasPermission()) {
          await _timeOverlayService.requestPermission();
          _toast('请允许显示在其他应用上层，然后返回再次开启');
          return;
        }
        await _timeOverlayService.show();
      } else {
        await _timeOverlayService.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _refreshOverlayState();
    } catch (error) {
      _toast('时间悬浮窗操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  Future<void> _openTelegramPlugin() async {
    if (!await _optionalFeatureGate.ensureAvailable(
      context,
      OptionalFeatureId.telegram,
    )) {
      return;
    }
    if (mounted) {
      await Navigator.pushNamed(context, '/telegram-checkin');
    }
  }

  Future<void> _openEasyTierPlugin() async {
    if (!await _optionalFeatureGate.ensureAvailable(
      context,
      OptionalFeatureId.easyTier,
    )) {
      return;
    }
    if (mounted) {
      await Navigator.pushNamed(context, '/easytier');
    }
  }

  Future<void> _openLifeRuntime() async {
    if (!await _optionalFeatureGate.ensureAvailable(
      context,
      OptionalFeatureId.lifeRuntime,
    )) {
      return;
    }
    if (mounted) await Navigator.pushNamed(context, '/life-runtime');
  }

  @override
  Widget build(BuildContext context) {
    if (_hiddenToolIds == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('小工具')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('小工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolSection(
            title: '通讯与协作',
            children: [
              if (_visible(ToolVisibilityStore.tg))
                _ToolTile(
                  icon: Icons.telegram,
                  label: 'TG 工具',
                  onTap: () => unawaited(_openTelegramPlugin()),
                ),
              if (_visible(ToolVisibilityStore.chat))
                _ToolTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '聊天工具',
                  onTap: () => Navigator.pushNamed(context, '/ai-chat'),
                ),
              _ToolTile(
                icon: Icons.content_paste_rounded,
                label: '剪贴板',
                onTap: () => Navigator.pushNamed(context, '/clipboard'),
              ),
              if (_visible(ToolVisibilityStore.remoteControl))
                _ToolTile(
                  icon: Icons.control_camera_rounded,
                  label: '远程控制',
                  onTap: () => Navigator.pushNamed(context, '/remote-control'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _ToolSection(
            title: '网络与文件',
            children: [
              _ToolTile(
                icon: Icons.folder_shared_outlined,
                label: 'HTTP 文件',
                onTap: () =>
                    Navigator.pushNamed(context, '/local-http-settings'),
              ),
              _ToolTile(
                icon: Icons.edit_document,
                label: '文件管理',
                onTap: () =>
                    Navigator.pushNamed(context, '/simple-file-manager'),
              ),
              if (_visible(ToolVisibilityStore.p2pVpn))
                _ToolTile(
                  icon: Icons.vpn_lock_rounded,
                  label: 'P2P VPN',
                  onTap: () => unawaited(_openEasyTierPlugin()),
                ),
              if (_visible(ToolVisibilityStore.lifeRuntime))
                _ToolTile(
                  icon: Icons.auto_stories_rounded,
                  label: '人生运行时',
                  onTap: () => unawaited(_openLifeRuntime()),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _ToolSection(
            title: '日常工具',
            children: [
              if (_visible(ToolVisibilityStore.calculator))
                _ToolTile(
                  icon: Icons.calculate_rounded,
                  label: '计算器',
                  onTap: () => Navigator.pushNamed(context, '/calculator'),
                ),
              if (_visible(ToolVisibilityStore.translation))
                _ToolTile(
                  icon: Icons.translate_rounded,
                  label: '翻译工具',
                  onTap: () =>
                      Navigator.pushNamed(context, '/translation-tool'),
                ),
              if (_visible(ToolVisibilityStore.music))
                _ToolTile(
                  icon: Icons.library_music_rounded,
                  label: '音乐',
                  onTap: () => Navigator.pushNamed(context, '/music-player'),
                ),
              if (_visible(ToolVisibilityStore.game2048))
                _ToolTile(
                  icon: Icons.grid_view_rounded,
                  label: '2048',
                  onTap: () => Navigator.pushNamed(context, '/game-2048'),
                ),
              _ToolTile(
                icon: Icons.schedule_rounded,
                label: '时间悬浮窗',
                active: _timeOverlayRunning,
                busy: _busy,
                onTap: _busy
                    ? null
                    : () => unawaited(_toggleTimeOverlay(!_timeOverlayRunning)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: children,
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(
                active ? Icons.check_circle_rounded : icon,
                size: 30,
                color: active ? colorScheme.primary : null,
              ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
            if (active) ...[
              const SizedBox(height: 2),
              Text(
                '已开启',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
