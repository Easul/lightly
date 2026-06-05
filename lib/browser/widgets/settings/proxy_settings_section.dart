import 'package:flutter/material.dart';

import '../../browser_settings.dart';
import 'settings_section_widgets.dart';

class ProxySettingsSection extends StatelessWidget {
  const ProxySettingsSection({
    super.key,
    required this.enabled,
    required this.supported,
    required this.isSaving,
    required this.stateLabel,
    required this.stateColor,
    required this.detailText,
    required this.nodeLinkController,
    required this.proxyNodes,
    required this.selectedProxyNodeId,
    required this.errorMessage,
    required this.selectedProtocol,
    required this.showsUuidField,
    required this.showsTransportFields,
    required this.showsHysteria2ObfsFields,
    required this.showsPacketEncodingField,
    required this.showsTlsFields,
    required this.proxyTlsEnabled,
    required this.selectedTransportType,
    required this.proxyPacketEncoding,
    required this.proxyTlsInsecure,
    required this.proxyHostController,
    required this.proxyPortController,
    required this.localProxyPortController,
    required this.proxyUuidController,
    required this.proxyServerNameController,
    required this.proxyTransportPathController,
    required this.proxyTransportHostController,
    required this.proxyBypassDomainsController,
    required this.onToggle,
    required this.onParse,
    required this.onTestSpeed,
    required this.onAddProxyNode,
    required this.onSelectProxyNode,
    required this.onDeleteProxyNode,
    required this.onConfigurationChanged,
    required this.onProtocolChanged,
    required this.onTlsEnabledChanged,
    required this.onTransportTypeChanged,
    required this.onPacketEncodingChanged,
    required this.onTlsInsecureChanged,
  });

  final bool enabled;
  final bool supported;
  final bool isSaving;
  final String stateLabel;
  final Color stateColor;
  final String detailText;
  final TextEditingController nodeLinkController;
  final List<BrowserProxyNode> proxyNodes;
  final String? selectedProxyNodeId;
  final String? errorMessage;
  final String selectedProtocol;
  final bool showsUuidField;
  final bool showsTransportFields;
  final bool showsHysteria2ObfsFields;
  final bool showsPacketEncodingField;
  final bool showsTlsFields;
  final bool proxyTlsEnabled;
  final String selectedTransportType;
  final String proxyPacketEncoding;
  final bool proxyTlsInsecure;
  final TextEditingController proxyHostController;
  final TextEditingController proxyPortController;
  final TextEditingController localProxyPortController;
  final TextEditingController proxyUuidController;
  final TextEditingController proxyServerNameController;
  final TextEditingController proxyTransportPathController;
  final TextEditingController proxyTransportHostController;
  final TextEditingController proxyBypassDomainsController;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onParse;
  final Future<void> Function() onTestSpeed;
  final VoidCallback onAddProxyNode;
  final ValueChanged<String> onSelectProxyNode;
  final ValueChanged<String> onDeleteProxyNode;
  final VoidCallback onConfigurationChanged;
  final ValueChanged<String> onProtocolChanged;
  final ValueChanged<bool> onTlsEnabledChanged;
  final ValueChanged<String> onTransportTypeChanged;
  final ValueChanged<String> onPacketEncodingChanged;
  final ValueChanged<bool> onTlsInsecureChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProxyStatusCard(
          enabled: enabled,
          supported: supported,
          isSaving: isSaving,
          stateLabel: stateLabel,
          stateColor: stateColor,
          detailText: detailText,
          onToggle: onToggle,
        ),
        const SizedBox(height: 16),
        _NodeLinkParserCard(
          nodeLinkController: nodeLinkController,
          isSaving: isSaving,
          errorMessage: errorMessage,
          onParse: onParse,
          onTestSpeed: onTestSpeed,
        ),
        const SizedBox(height: 16),
        _ProxyNodeListCard(
          nodes: proxyNodes,
          selectedNodeId: selectedProxyNodeId,
          onAddProxyNode: onAddProxyNode,
          onSelectProxyNode: onSelectProxyNode,
          onDeleteProxyNode: onDeleteProxyNode,
        ),
        const SizedBox(height: 16),
        SettingsCard(
          children: [
            ProxyConfigurationForm(
              selectedProtocol: selectedProtocol,
              proxyEnabled: enabled,
              showsUuidField: showsUuidField,
              showsTransportFields: showsTransportFields,
              showsHysteria2ObfsFields: showsHysteria2ObfsFields,
              showsPacketEncodingField: showsPacketEncodingField,
              showsTlsFields: showsTlsFields,
              proxyTlsEnabled: proxyTlsEnabled,
              selectedTransportType: selectedTransportType,
              proxyPacketEncoding: proxyPacketEncoding,
              proxyTlsInsecure: proxyTlsInsecure,
              proxyHostController: proxyHostController,
              proxyPortController: proxyPortController,
              localProxyPortController: localProxyPortController,
              proxyUuidController: proxyUuidController,
              proxyServerNameController: proxyServerNameController,
              proxyTransportPathController: proxyTransportPathController,
              proxyTransportHostController: proxyTransportHostController,
              proxyBypassDomainsController: proxyBypassDomainsController,
              onConfigurationChanged: onConfigurationChanged,
              onProtocolChanged: onProtocolChanged,
              onTlsEnabledChanged: onTlsEnabledChanged,
              onTransportTypeChanged: onTransportTypeChanged,
              onPacketEncodingChanged: onPacketEncodingChanged,
              onTlsInsecureChanged: onTlsInsecureChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProxyNodeListCard extends StatelessWidget {
  const _ProxyNodeListCard({
    required this.nodes,
    required this.selectedNodeId,
    required this.onAddProxyNode,
    required this.onSelectProxyNode,
    required this.onDeleteProxyNode,
  });

  final List<BrowserProxyNode> nodes;
  final String? selectedNodeId;
  final VoidCallback onAddProxyNode;
  final ValueChanged<String> onSelectProxyNode;
  final ValueChanged<String> onDeleteProxyNode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsCard(
      children: [
        Row(
          children: [
            const Icon(Icons.storage_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '代理节点列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '点击节点可填充到上方表单；保存设置时会更新当前选中节点。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onAddProxyNode,
              icon: const Icon(Icons.add),
              label: const Text('添加当前'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (nodes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              '还没有保存的节点。可解析节点链接后自动加入，或填写表单后点“添加当前”。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...nodes.map((node) {
            final selected = node.id == selectedNodeId;
            final port = node.proxyPort?.toString() ?? '-';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                leading: CircleAvatar(
                  backgroundColor: selected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  child: Text(
                    BrowserProxyProtocol.label(
                      node.proxyProtocol,
                    ).substring(0, 1),
                  ),
                ),
                title: Text(
                  node.name.trim().isEmpty ? '未命名节点' : node.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${BrowserProxyProtocol.label(node.proxyProtocol)} · ${node.proxyHost}:$port',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selected,
                onTap: () => onSelectProxyNode(node.id),
                trailing: IconButton(
                  tooltip: '删除节点',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDeleteProxyNode(node.id),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class ProxyConfigurationForm extends StatelessWidget {
  const ProxyConfigurationForm({
    super.key,
    required this.selectedProtocol,
    required this.proxyEnabled,
    required this.showsUuidField,
    required this.showsTransportFields,
    required this.showsHysteria2ObfsFields,
    required this.showsPacketEncodingField,
    required this.showsTlsFields,
    required this.proxyTlsEnabled,
    required this.selectedTransportType,
    required this.proxyPacketEncoding,
    required this.proxyTlsInsecure,
    required this.proxyHostController,
    required this.proxyPortController,
    required this.localProxyPortController,
    required this.proxyUuidController,
    required this.proxyServerNameController,
    required this.proxyTransportPathController,
    required this.proxyTransportHostController,
    required this.proxyBypassDomainsController,
    required this.onConfigurationChanged,
    required this.onProtocolChanged,
    required this.onTlsEnabledChanged,
    required this.onTransportTypeChanged,
    required this.onPacketEncodingChanged,
    required this.onTlsInsecureChanged,
  });

  final String selectedProtocol;
  final bool proxyEnabled;
  final bool showsUuidField;
  final bool showsTransportFields;
  final bool showsHysteria2ObfsFields;
  final bool showsPacketEncodingField;
  final bool showsTlsFields;
  final bool proxyTlsEnabled;
  final String selectedTransportType;
  final String proxyPacketEncoding;
  final bool proxyTlsInsecure;
  final TextEditingController proxyHostController;
  final TextEditingController proxyPortController;
  final TextEditingController localProxyPortController;
  final TextEditingController proxyUuidController;
  final TextEditingController proxyServerNameController;
  final TextEditingController proxyTransportPathController;
  final TextEditingController proxyTransportHostController;
  final TextEditingController proxyBypassDomainsController;
  final VoidCallback onConfigurationChanged;
  final ValueChanged<String> onProtocolChanged;
  final ValueChanged<bool> onTlsEnabledChanged;
  final ValueChanged<String> onTransportTypeChanged;
  final ValueChanged<String> onPacketEncodingChanged;
  final ValueChanged<bool> onTlsInsecureChanged;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      DropdownButtonFormField<String>(
        initialValue: selectedProtocol,
        decoration: const InputDecoration(
          labelText: '代理协议',
          prefixIcon: Icon(Icons.settings_ethernet_outlined),
        ),
        items: BrowserProxyProtocol.values
            .map(
              (protocol) => DropdownMenuItem<String>(
                value: protocol,
                child: Text(BrowserProxyProtocol.label(protocol)),
              ),
            )
            .toList(),
        onChanged: !proxyEnabled
            ? null
            : (value) {
                if (value != null) {
                  onProtocolChanged(value);
                }
              },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: proxyHostController,
        enabled: proxyEnabled,
        onChanged: (_) => onConfigurationChanged(),
        decoration: InputDecoration(
          labelText: selectedProtocol == BrowserProxyProtocol.http
              ? 'HTTP 代理地址'
              : '服务器地址',
          prefixIcon: const Icon(Icons.dns_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: proxyPortController,
        enabled: proxyEnabled,
        onChanged: (_) => onConfigurationChanged(),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '服务器端口',
          prefixIcon: Icon(Icons.pin_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: localProxyPortController,
        enabled: proxyEnabled,
        onChanged: (_) => onConfigurationChanged(),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '本地代理端口（HTTP + SOCKS5，留空随机）',
          prefixIcon: Icon(Icons.swap_horiz_outlined),
        ),
      ),
    ];

    if (showsUuidField) {
      fields.addAll([
        const SizedBox(height: 12),
        TextField(
          controller: proxyUuidController,
          enabled: proxyEnabled,
          onChanged: (_) => onConfigurationChanged(),
          decoration: InputDecoration(
            labelText: selectedProtocol == BrowserProxyProtocol.http
                ? '密码（可选）'
                : selectedProtocol == BrowserProxyProtocol.hysteria2
                ? '认证密码 / Auth'
                : 'UUID',
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
      ]);
    }

    if (showsTransportFields) {
      fields.addAll([
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedTransportType,
          decoration: const InputDecoration(
            labelText: '传输方式',
            prefixIcon: Icon(Icons.route_outlined),
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('直接连接')),
            DropdownMenuItem(value: 'ws', child: Text('WebSocket')),
          ],
          onChanged: !proxyEnabled
              ? null
              : (value) => onTransportTypeChanged(value ?? ''),
        ),
        if (selectedTransportType == 'ws') ...[
          const SizedBox(height: 12),
          TextField(
            controller: proxyTransportPathController,
            enabled: proxyEnabled,
            onChanged: (_) => onConfigurationChanged(),
            decoration: const InputDecoration(
              labelText: 'WebSocket 路径',
              hintText: '/path',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: proxyTransportHostController,
            enabled: proxyEnabled,
            onChanged: (_) => onConfigurationChanged(),
            decoration: const InputDecoration(
              labelText: 'WebSocket Host 头（可选）',
              prefixIcon: Icon(Icons.http_outlined),
            ),
          ),
        ],
      ]);
    }

    if (showsHysteria2ObfsFields) {
      fields.addAll([
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedTransportType,
          decoration: const InputDecoration(
            labelText: '混淆方式',
            helperText: 'Hysteria2 常用 salamander；不需要混淆则保持关闭',
            prefixIcon: Icon(Icons.route_outlined),
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('关闭混淆')),
            DropdownMenuItem(value: 'salamander', child: Text('salamander')),
          ],
          onChanged: !proxyEnabled
              ? null
              : (value) => onTransportTypeChanged(value ?? ''),
        ),
        if (selectedTransportType.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextField(
            controller: proxyTransportHostController,
            enabled: proxyEnabled,
            onChanged: (_) => onConfigurationChanged(),
            decoration: const InputDecoration(
              labelText: '混淆密码',
              prefixIcon: Icon(Icons.password_outlined),
            ),
          ),
        ],
      ]);
    }

    if (showsTlsFields) {
      fields.addAll([
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: proxyTlsEnabled,
          title: const Text('启用 TLS'),
          subtitle: const Text('443 或要求 tls 的节点请保持开启'),
          onChanged: !proxyEnabled ? null : onTlsEnabledChanged,
        ),
        if (showsPacketEncodingField) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: proxyPacketEncoding,
            decoration: const InputDecoration(
              labelText: '数据包编码',
              helperText: 'OpenAI Workers 等 VLESS 节点可能需要 xudp',
              prefixIcon: Icon(Icons.tune_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('默认')),
              DropdownMenuItem(value: 'xudp', child: Text('xudp')),
            ],
            onChanged: !proxyEnabled
                ? null
                : (value) => onPacketEncodingChanged(value ?? ''),
          ),
        ],
        if (proxyTlsEnabled ||
            selectedProtocol == BrowserProxyProtocol.hysteria2) ...[
          const SizedBox(height: 12),
          TextField(
            controller: proxyServerNameController,
            enabled: proxyEnabled,
            onChanged: (_) => onConfigurationChanged(),
            decoration: const InputDecoration(
              labelText: 'TLS 服务器名称（SNI，可选）',
              helperText: '与证书域名不一致时可手动填写',
              prefixIcon: Icon(Icons.security_outlined),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: proxyTlsInsecure,
            title: const Text('允许不安全证书'),
            subtitle: const Text('证书校验失败但节点确认可信时再开启'),
            onChanged: !proxyEnabled ? null : onTlsInsecureChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '如果出现 TLS 握手失败、Cloudflare/Workers 证书不匹配或自签证书场景，可尝试开启此项。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ]);
    }

    fields.addAll([
      const SizedBox(height: 12),
      TextField(
        controller: proxyBypassDomainsController,
        enabled: proxyEnabled,
        onChanged: (_) => onConfigurationChanged(),
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: '不走代理的域名',
          hintText: 'localhost\nexample.com\ninternal.company',
          prefixIcon: Icon(Icons.alt_route_outlined),
          helperText: '每行或逗号分隔一个域名；localhost 默认始终直连',
        ),
      ),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }
}

class _ProxyStatusCard extends StatelessWidget {
  const _ProxyStatusCard({
    required this.enabled,
    required this.supported,
    required this.isSaving,
    required this.stateLabel,
    required this.stateColor,
    required this.detailText,
    required this.onToggle,
  });

  final bool enabled;
  final bool supported;
  final bool isSaving;
  final String stateLabel;
  final Color stateColor;
  final String detailText;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: const Text('启用代理'),
          subtitle: Text(supported ? '通过代理访问外网（仅浏览器生效）' : '代理仅在 Android 上可用'),
          onChanged: !supported || isSaving ? null : onToggle,
        ),
        const Divider(),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '代理状态：$stateLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        Text(detailText, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _NodeLinkParserCard extends StatelessWidget {
  const _NodeLinkParserCard({
    required this.nodeLinkController,
    required this.isSaving,
    required this.errorMessage,
    required this.onParse,
    required this.onTestSpeed,
  });

  final TextEditingController nodeLinkController;
  final bool isSaving;
  final String? errorMessage;
  final Future<void> Function() onParse;
  final Future<void> Function() onTestSpeed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsCard(
      children: [
        TextField(
          controller: nodeLinkController,
          decoration: const InputDecoration(
            labelText: '粘贴 vless:// 或 http:// 链接',
            hintText:
                'vless://uuid@host:port?... 或 hysteria2://password@host:port?...',
            prefixIcon: Icon(Icons.content_paste_outlined),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: onParse,
            child: const Text('解析并应用'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: isSaving ? null : onTestSpeed,
            child: const Text('节点测速'),
          ),
        ),
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(errorMessage!, style: TextStyle(color: colorScheme.error)),
        ],
      ],
    );
  }
}
