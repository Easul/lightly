import 'dart:async';

import 'package:flutter/material.dart';

import '../app/optional_feature_coordinator.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';
import '../features/optional_plugins/domain/optional_feature.dart';
import '../features/optional_plugins/domain/optional_plugin_download_settings.dart';
import '../features/optional_plugins/domain/optional_plugin_manifest.dart';
import '../features/optional_plugins/infrastructure/optional_plugin_download_settings_store.dart';
import '../services/app_toast.dart';

class OptionalPluginSettingsPage extends StatefulWidget {
  const OptionalPluginSettingsPage({
    super.key,
    this.settingsStore,
    this.coordinator,
  });

  final OptionalPluginDownloadSettingsStore? settingsStore;
  final OptionalFeatureCoordinator? coordinator;

  @override
  State<OptionalPluginSettingsPage> createState() =>
      _OptionalPluginSettingsPageState();
}

class _OptionalPluginSettingsPageState
    extends State<OptionalPluginSettingsPage> {
  late final OptionalPluginDownloadSettingsStore _settingsStore;
  late final OptionalFeatureCoordinator _coordinator;
  late final TextEditingController _mirrorPrefixController;

  OptionalPluginDownloadMode _mode = OptionalPluginDownloadMode.automatic;
  OptionalPluginManifest? _manifest;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _settingsStore =
        widget.settingsStore ?? OptionalPluginDownloadSettingsStore();
    _coordinator = widget.coordinator ?? OptionalFeatureCoordinator.instance;
    _mirrorPrefixController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _mirrorPrefixController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    OptionalPluginManifest? manifest;
    try {
      manifest = await _coordinator.loadBundledManifest();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _mode = settings.mode;
      _mirrorPrefixController.text = settings.normalizedMirrorPrefix;
      _manifest = manifest;
      _loading = false;
    });
  }

  OptionalPluginDownloadSettings _currentSettings() {
    return OptionalPluginDownloadSettings(
      mode: _mode,
      mirrorPrefix: _mirrorPrefixController.text,
    );
  }

  Future<bool> _save({
    bool closeAfterSave = false,
    bool showMessage = true,
  }) async {
    final settings = _currentSettings();
    final error = settings.validationError;
    if (error != null) {
      unawaited(AppToast.show(error));
      return false;
    }
    setState(() => _saving = true);
    try {
      await _settingsStore.save(settings);
      _mirrorPrefixController.text = settings.normalizedMirrorPrefix;
      if (!mounted) {
        return true;
      }
      if (showMessage) {
        unawaited(AppToast.show('插件下载设置已保存'));
      }
      if (closeAfterSave) {
        Navigator.of(context).pop();
      }
      return true;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _testRoute() async {
    if (_testing || _saving || !await _save(showMessage: false)) {
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final result = await _coordinator.testDownloadRoute();
      if (!mounted) {
        return;
      }
      setState(() {
        _testResult =
            '${result.routeLabel}可用，首包 ${result.elapsed.inMilliseconds} ms';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _testResult = '线路测试失败：$error');
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件下载'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _saving || _loading
                ? null
                : () => _save(closeAfterSave: true),
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                SettingsCard(
                  children: [
                    SegmentedButton<OptionalPluginDownloadMode>(
                      segments: const [
                        ButtonSegment(
                          value: OptionalPluginDownloadMode.automatic,
                          icon: Icon(Icons.alt_route_outlined),
                          label: Text('自动'),
                        ),
                        ButtonSegment(
                          value: OptionalPluginDownloadMode.githubOnly,
                          icon: Icon(Icons.cloud_outlined),
                          label: Text('GitHub'),
                        ),
                        ButtonSegment(
                          value: OptionalPluginDownloadMode.mirrorOnly,
                          icon: Icon(Icons.speed_outlined),
                          label: Text('镜像'),
                        ),
                      ],
                      selected: <OptionalPluginDownloadMode>{_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _mode = selection.single);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _mirrorPrefixController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'GitHub 镜像前缀',
                        prefixIcon: Icon(Icons.link_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _testing ? null : _testRoute,
                        icon: Icon(
                          _testing
                              ? Icons.hourglass_top_rounded
                              : Icons.network_check_outlined,
                        ),
                        label: Text(_testing ? '正在测试' : '测试下载线路'),
                      ),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _testResult!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SettingsCard(children: _buildReleaseRows(context)),
              ],
            ),
    );
  }

  List<Widget> _buildReleaseRows(BuildContext context) {
    final manifest = _manifest;
    if (manifest == null) {
      return const <Widget>[
        ListTile(contentPadding: EdgeInsets.zero, title: Text('包内插件清单不可用')),
      ];
    }
    final rows = <Widget>[];
    for (final featureId in OptionalFeatureId.values) {
      final descriptor = OptionalFeatureCatalog.descriptor(featureId);
      final release = manifest.releaseFor(featureId);
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1));
      }
      rows.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(descriptor.displayName),
          subtitle: Text(
            release == null
                ? '当前 Lightly 未固定该插件版本'
                : '${release.versionName} · API ${release.apiVersion}',
          ),
          trailing: const Icon(Icons.verified_outlined),
        ),
      );
    }
    return rows;
  }
}
