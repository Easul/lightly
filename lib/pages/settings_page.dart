import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser/browser_settings.dart';
import '../browser/local_http_file_server_service.dart';
import '../browser/browser_settings_service.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_subscription_service.dart';
import '../browser/services/browser_node_link_parser.dart';
import '../browser/services/browser_proxy_status_monitor.dart';
import '../browser/services/browser_settings_action_handler.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../browser/services/browser_settings_runtime_service.dart';
import '../browser/services/browser_shared_services.dart';
import '../browser/widgets/settings/clear_browsing_data_dialog.dart';
import '../browser/widgets/settings/general_settings_section.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';
import '../browser/widgets/settings/video_settings_section.dart';
import '../services/app_toast.dart';
import 'settings_page_home_sections.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final BrowserSharedServices _sharedServices = BrowserSharedServices.instance;
  BrowserSettingsService get _settingsService =>
      _sharedServices.settingsService;
  ProxyService get _proxyService => _sharedServices.proxyService;
  LocalHttpFileServerService get _localHttpFileServerService =>
      _sharedServices.localHttpFileServerService;
  BrowserSubscriptionService get _subscriptionService =>
      _sharedServices.subscriptionService;
  late final BrowserNodeLinkParser _nodeLinkParser;
  late final BrowserProxyStatusMonitor _statusMonitor;
  late final BrowserSettingsActionHandler _settingsActionHandler;
  late final BrowserSettingsRuntimeService _runtimeService;
  final _formController = BrowserSettingsFormController();

  bool _proxySupported = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasAppliedChanges = false;
  String? _errorMessage;
  ProxyState get _proxyState => _statusMonitor.proxyState.value;
  LocalHttpFileServerState get _localHttpState =>
      _statusMonitor.localHttpState.value;

  @override
  void initState() {
    super.initState();
    _nodeLinkParser = BrowserNodeLinkParser(
      subscriptionService: _subscriptionService,
    );
    _settingsActionHandler = BrowserSettingsActionHandler();
    _runtimeService = BrowserSettingsRuntimeService(
      saveSettings: _settingsService.saveSettings,
      applyProxy: _proxyService.applyProxy,
      clearProxy: _proxyService.clearProxy,
      applyLocalHttpSettings: _localHttpFileServerService.applySettings,
      stopLocalHttpServer: _localHttpFileServerService.stop,
    );
    _statusMonitor = BrowserProxyStatusMonitor(
      proxyService: _proxyService,
      localHttpFileServerService: _localHttpFileServerService,
    );
    _statusMonitor.proxyState.addListener(_handleStatusMonitorChanged);
    _statusMonitor.localHttpState.addListener(_handleStatusMonitorChanged);
    _statusMonitor.start();
    _loadSettings();
  }

  @override
  void dispose() {
    _formController.dispose();
    _statusMonitor.proxyState.removeListener(_handleStatusMonitorChanged);
    _statusMonitor.localHttpState.removeListener(_handleStatusMonitorChanged);
    _statusMonitor.dispose();
    super.dispose();
  }

  void _handleStatusMonitorChanged() {
    _updateState(() {});
  }

  void _updateState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _markSectionDirty();
  }

  void _markSectionDirty() {
    _formController.markDirty();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    final proxySupported = await _proxyService.isSupported();
    if (!mounted) return;
    setState(() {
      _formController.applySettings(settings);
      _proxySupported = proxySupported;
      _statusMonitor.syncSnapshot();
      _isLoading = false;
    });
  }

  void _applyProxySettingsToForm(BrowserSettings settings) {
    _formController.applySettings(settings);
  }

  Future<void> _parseNodeLink() async {
    final link = _formController.nodeLinkController.text.trim();
    if (link.isEmpty) {
      _showSnackBar('请输入节点链接');
      return;
    }

    setState(() {
      _errorMessage = null;
    });
    _markSectionDirty();

    try {
      final result = _nodeLinkParser.parseNodeLink(
        link,
        currentSettings: _buildSettingsFromForm(),
      );
      setState(() {
        _applyProxySettingsToForm(result.settings);
        _errorMessage = null;
      });
      _markSectionDirty();
      _showSnackBar('已解析并应用节点：${result.node.name}');
    } on BrowserNodeLinkParserException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
      _markSectionDirty();
      _showSnackBar(error.message == '请输入节点链接' ? error.message : '节点链接格式无效');
    } catch (error) {
      setState(() {
        _errorMessage = '解析失败：$error';
      });
      _markSectionDirty();
      _showSnackBar('节点解析失败');
    }
  }

  Future<void> _testNodeSpeed() async {
    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });
    _markSectionDirty();

    try {
      final settings = _nodeLinkParser.resolveSettingsForSpeedTest(
        _formController.nodeLinkController.text,
        currentSettings: _buildSettingsFromForm(),
      );

      if (settings.proxyValidationError != null) {
        _showSnackBar(settings.proxyValidationError!);
        return;
      }

      final latency = await _proxyService.testNodeLatency(settings);
      if (!mounted) {
        return;
      }

      if (latency == null) {
        setState(() {
          _errorMessage = '测速失败：节点不可用或连接超时';
        });
        _showSnackBar('测速失败');
      } else {
        final message = '测速结果：${latency.inMilliseconds} ms';
        setState(() {
          _errorMessage = message;
        });
        _showSnackBar(message);
      }
    } on BrowserNodeLinkParserException catch (error) {
      _showSnackBar(error.message == '请输入节点链接' ? error.message : '节点链接格式无效');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is SocketException
          ? '测速失败：${error.message}'
          : '测速失败：$error';
      setState(() {
        _errorMessage = message;
      });
      _showSnackBar(message);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _markSectionDirty();
      }
    }
  }

  BrowserSettings _buildSettingsFromForm() {
    return _formController.buildSettings();
  }

  Future<void> _saveSettings({bool closeAfterSave = true}) async {
    final settings = _buildSettingsFromForm();
    final previousSettings = await _settingsService.loadSettings();
    if (settings.proxyValidationError != null) {
      _showSnackBar(settings.proxyValidationError!);
      return;
    }
    if (settings.localHttpServerValidationError != null) {
      _showSnackBar(settings.localHttpServerValidationError!);
      return;
    }
    final shouldRequireLocalHttpFileAccess =
        settings.localHttpServerEnabled &&
        (!previousSettings.localHttpServerEnabled ||
            settings.localHttpRootPath != previousSettings.localHttpRootPath);
    if (shouldRequireLocalHttpFileAccess) {
      final hasPermission = await _ensureLocalHttpFileAccessPermission();
      if (!hasPermission) {
        _showSnackBar('请先授予文件访问权限，才能托管手机目录');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });
    _markSectionDirty();

    try {
      final result = await _runtimeService.saveSettings(
        settings: settings,
        previousSettings: previousSettings,
      );
      _showSnackBar(result.message);

      if (!mounted) {
        return;
      }
      _hasAppliedChanges = result.appliedChanges;
      if (closeAfterSave) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _showSnackBar(_proxyService.describeError(error));
      if (!mounted) {
        return;
      }
      if (closeAfterSave) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _markSectionDirty();
      }
    }
  }

  Future<void> _handleProxyToggle(bool enabled) async {
    if (!_proxySupported) {
      return;
    }

    if (enabled) {
      final settings = _buildSettingsFromForm().copyWith(proxyEnabled: true);
      if (settings.proxyValidationError != null) {
        _showSnackBar(settings.proxyValidationError!);
        return;
      }

      setState(() {
        _formController.proxyEnabled = true;
        _statusMonitor.setProxyState(ProxyState.starting);
        _isSaving = true;
      });
      _markSectionDirty();

      try {
        final result = await _runtimeService.enableProxy(settings);
        _hasAppliedChanges = result.appliedChanges;
        _showSnackBar(result.message);
      } catch (error) {
        if (mounted) {
          setState(() {
            _formController.proxyEnabled = false;
          });
        }
        _showSnackBar(_proxyService.describeError(error));
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
            _statusMonitor.syncSnapshot();
          });
          _markSectionDirty();
        }
      }
      return;
    }

    await _stopProxy();
  }

  Future<void> _stopProxy() async {
    final settings = _buildSettingsFromForm().copyWith(proxyEnabled: false);
    setState(() {
      _formController.proxyEnabled = false;
      _statusMonitor.setProxyState(ProxyState.stopping);
      _isSaving = true;
    });
    _markSectionDirty();

    try {
      final result = await _runtimeService.disableProxy(settings);
      _hasAppliedChanges = result.appliedChanges;
      _showSnackBar(result.message);
    } catch (error) {
      _showSnackBar(_proxyService.describeError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMonitor.syncSnapshot();
        });
        _markSectionDirty();
      }
    }
  }

  Future<bool> _ensureLocalHttpFileAccessPermission() async {
    final result = await _settingsActionHandler
        .ensureLocalHttpFileAccessPermission();
    if (result.errorMessage != null) {
      _showSnackBar(result.errorMessage!);
    }
    return result.granted;
  }

  Future<void> _useSharedDownloadsDirectory() async {
    final path = await _settingsActionHandler.resolveSharedDownloadsDirectory();
    if (!mounted) {
      return;
    }
    if (path == null || path.trim().isEmpty) {
      _showSnackBar('无法获取系统下载目录');
      return;
    }
    setState(() {
      _formController.localHttpRootPathController.text = path;
    });
    _markSectionDirty();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    unawaited(AppToast.show(message));
  }

  Future<void> _showClearBrowsingDataDialog() async {
    final selection = await showClearBrowsingDataDialog(context);
    if (selection == null) {
      return;
    }
    if (selection.isEmpty) {
      _showSnackBar('请至少选择一项');
      return;
    }

    await _settingsActionHandler.clearBrowsingData(selection);
    _hasAppliedChanges = true;
    _showSnackBar('已清除所选浏览数据');
  }

  String get _proxyStateLabel {
    switch (_proxyState) {
      case ProxyState.started:
        return '已连接';
      case ProxyState.starting:
        return '连接中';
      case ProxyState.stopping:
        return '停止中';
      case ProxyState.stopped:
        return '未连接';
    }
  }

  String get _localHttpStateLabel {
    switch (_localHttpState) {
      case LocalHttpFileServerState.started:
        return '已启动';
      case LocalHttpFileServerState.starting:
        return '启动中';
      case LocalHttpFileServerState.stopping:
        return '停止中';
      case LocalHttpFileServerState.stopped:
        return '未启动';
    }
  }

  Color _proxyStateColor(ColorScheme colorScheme) {
    switch (_proxyState) {
      case ProxyState.started:
        return colorScheme.primary;
      case ProxyState.starting:
      case ProxyState.stopping:
        return colorScheme.primary;
      case ProxyState.stopped:
        return colorScheme.outline;
    }
  }

  Color _localHttpStateColor(ColorScheme colorScheme) {
    switch (_localHttpState) {
      case LocalHttpFileServerState.started:
        return colorScheme.primary;
      case LocalHttpFileServerState.starting:
      case LocalHttpFileServerState.stopping:
        return colorScheme.primary;
      case LocalHttpFileServerState.stopped:
        return colorScheme.outline;
    }
  }

  void _pushSection({
    required String title,
    required IconData icon,
    required List<Widget> Function(BuildContext context) buildChildren,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsSectionPage(
          title: title,
          icon: icon,
          revisionListenable: _formController.revision,
          isSavingBuilder: () => _isSaving,
          buildChildren: buildChildren,
          onSave: () => _saveSettings(closeAfterSave: false),
        ),
      ),
    );
  }

  Widget _buildGeneralSection() {
    return GeneralSettingsSection(
      homepageController: _formController.homepageController,
      openNewWindowInTab: _formController.openNewWindowInTab,
      onHomepageChanged: (_) => _markSectionDirty(),
      onOpenNewWindowInTabChanged: (value) {
        setState(() {
          _formController.openNewWindowInTab = value;
        });
        _markSectionDirty();
      },
      onClearBrowsingDataTap: _showClearBrowsingDataDialog,
    );
  }

  Widget _buildVideoSection() {
    return VideoSettingsSection(
      nativeVideoPlayerEnabled: _formController.nativeVideoPlayerEnabled,
      nativeVideoParserApiController:
          _formController.nativeVideoParserApiController,
      onNativeVideoPlayerEnabledChanged: (value) {
        setState(() {
          _formController.nativeVideoPlayerEnabled = value;
        });
        _markSectionDirty();
      },
      onParserApiChanged: (_) => _markSectionDirty(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_hasAppliedChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_hasAppliedChanges),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SettingsPageHomeSections(
                    buildGeneralSection: _buildGeneralSection,
                    buildVideoSection: _buildVideoSection,
                    pushSection: _pushSection,
                    formController: _formController,
                    proxySupported: _proxySupported,
                    isSaving: _isSaving,
                    proxyStateLabel: _proxyStateLabel,
                    proxyStateColor: _proxyStateColor,
                    localHttpStateLabel: _localHttpStateLabel,
                    localHttpStateColor: _localHttpStateColor,
                    proxyService: _proxyService,
                    localHttpFileServerService: _localHttpFileServerService,
                    errorMessage: _errorMessage,
                    onHandleProxyToggle: _handleProxyToggle,
                    onParseNodeLink: _parseNodeLink,
                    onTestNodeSpeed: _testNodeSpeed,
                    onProxyProtocolChanged: (value) {
                      setState(() {
                        _formController.selectedProtocol = value;
                        if (!_formController.showsTransportFields) {
                          _formController.selectedTransportType = '';
                          _formController.proxyPacketEncoding = '';
                        }
                        if (_formController.selectedProtocol ==
                            BrowserProxyProtocol.vless) {
                          _formController.proxyTlsEnabled = true;
                        } else {
                          _formController.proxyTlsEnabled = false;
                          _formController.proxyTlsInsecure = false;
                        }
                      });
                      _markSectionDirty();
                    },
                    onProxyTlsEnabledChanged: (value) {
                      setState(() {
                        _formController.proxyTlsEnabled = value;
                        if (!value) {
                          _formController.proxyTlsInsecure = false;
                        }
                      });
                      _markSectionDirty();
                    },
                    onProxyTransportTypeChanged: (value) {
                      setState(() {
                        _formController.selectedTransportType = value;
                      });
                      _markSectionDirty();
                    },
                    onProxyPacketEncodingChanged: (value) {
                      setState(() {
                        _formController.proxyPacketEncoding = value;
                      });
                      _markSectionDirty();
                    },
                    onProxyTlsInsecureChanged: (value) {
                      setState(() {
                        _formController.proxyTlsInsecure = value;
                      });
                      _markSectionDirty();
                    },
                    onLocalHttpToggle: (value) {
                      setState(() {
                        _formController.localHttpServerEnabled = value;
                      });
                      _markSectionDirty();
                    },
                    onLocalHttpBindAllInterfacesChanged: (value) {
                      setState(() {
                        _formController.localHttpBindAllInterfaces = value;
                      });
                      _markSectionDirty();
                    },
                    onUseSharedDownloadsDirectory: _useSharedDownloadsDirectory,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
        bottomNavigationBar: _isLoading
            ? null
            : SettingsHomeBottomActions(
                isSaving: _isSaving,
                onCancel: () => Navigator.of(context).pop(_hasAppliedChanges),
                onSave: _saveSettings,
              ),
      ),
    );
  }
}
