import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_toast.dart';
import '../services/time_overlay_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> with WidgetsBindingObserver {
  final TimeOverlayService _timeOverlayService = TimeOverlayService();
  bool _timeOverlayRunning = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshOverlayState());
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
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              _ToolTile(
                icon: Icons.telegram,
                label: 'TG 工具',
                onTap: () => Navigator.pushNamed(context, '/telegram-checkin'),
              ),
              _ToolTile(
                icon: Icons.calculate_rounded,
                label: '计算器',
                onTap: () => Navigator.pushNamed(context, '/calculator'),
              ),
              _ToolTile(
                icon: Icons.grid_view_rounded,
                label: '2048',
                onTap: () => Navigator.pushNamed(context, '/game-2048'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: _timeOverlayRunning,
              onChanged: _busy ? null : _toggleTimeOverlay,
              secondary: const Icon(Icons.schedule_rounded),
              title: const Text('系统时间悬浮窗'),
              subtitle: const Text('在其他应用上方显示手机系统时分秒，可拖动位置'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
            Icon(icon, size: 30),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
