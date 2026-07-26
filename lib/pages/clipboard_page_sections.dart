import 'package:flutter/material.dart';

import '../features/local_sharing/clipboard/clipboard_http_server_service.dart';

class ClipboardServerStatusCard extends StatelessWidget {
  const ClipboardServerStatusCard({
    super.key,
    required this.server,
    required this.serverEnabled,
    required this.serverState,
    required this.portController,
    required this.onToggleServer,
  });

  final ClipboardHttpServerService server;
  final bool serverEnabled;
  final ClipboardHttpServerState serverState;
  final TextEditingController portController;
  final ValueChanged<bool> onToggleServer;

  String get _statusLabel {
    switch (serverState) {
      case ClipboardHttpServerState.started:
        return '运行中';
      case ClipboardHttpServerState.starting:
        return '启动中...';
      case ClipboardHttpServerState.stopping:
        return '停止中...';
      case ClipboardHttpServerState.stopped:
        return '已停止';
    }
  }

  Color _statusColor(ColorScheme colorScheme) {
    switch (serverState) {
      case ClipboardHttpServerState.started:
      case ClipboardHttpServerState.starting:
      case ClipboardHttpServerState.stopping:
        return colorScheme.primary;
      case ClipboardHttpServerState.stopped:
        return colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor(colorScheme),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'HTTP 服务状态：$_statusLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: serverEnabled,
              title: const Text('启用剪贴板网页服务'),
              subtitle: const Text('通过局域网访问和编辑剪贴板内容'),
              onChanged: onToggleServer,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              enabled: !serverEnabled,
              decoration: const InputDecoration(
                labelText: '服务端口（留空则随机）',
                prefixIcon: Icon(Icons.settings_ethernet_outlined),
              ),
            ),
            if (server.isRunning) ...[
              const SizedBox(height: 8),
              _ClipboardServerInfoLine(text: '监听地址：${server.baseUrl ?? ''}'),
              _ClipboardServerInfoLine(text: '本机访问：${server.localUrl ?? ''}'),
              for (final lanUrl in server.lanUrls)
                _ClipboardServerInfoLine(text: '局域网访问：$lanUrl'),
            ],
          ],
        ),
      ),
    );
  }
}

class ClipboardEditorSection extends StatelessWidget {
  const ClipboardEditorSection({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.contextMenuBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final EditableTextContextMenuBuilder contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('剪贴板内容', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: RawScrollbar(
              controller: scrollController,
              thumbVisibility: true,
              radius: const Radius.circular(8),
              thickness: 4,
              crossAxisMargin: 3,
              mainAxisMargin: 4,
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                scrollController: scrollController,
                maxLines: null,
                minLines: 8,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '在此输入或粘贴内容...',
                  alignLabelWithHint: false,
                  contentPadding: EdgeInsets.fromLTRB(12, 12, 18, 12),
                ),
                contextMenuBuilder: contextMenuBuilder,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ClipboardUndoRedoRow extends StatelessWidget {
  const ClipboardUndoRedoRow({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_outlined),
            label: const Text('撤销'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo_outlined),
            label: const Text('恢复'),
          ),
        ),
      ],
    );
  }
}

class ClipboardActionButtons extends StatelessWidget {
  const ClipboardActionButtons({
    super.key,
    required this.isSaving,
    required this.onSave,
    required this.onPaste,
    required this.onRefresh,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onPaste;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(isSaving ? '保存中...' : '保存到剪贴板'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_outlined),
                label: const Text('从剪贴板粘贴'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('刷新已保存内容'),
          ),
        ),
      ],
    );
  }
}

class _ClipboardServerInfoLine extends StatelessWidget {
  const _ClipboardServerInfoLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.15),
      ),
    );
  }
}
