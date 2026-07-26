import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../browser/browser_settings.dart';
import '../features/local_sharing/local_http/local_http_file_server_service.dart';
import '../browser/browser_settings_service.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_subscription_service.dart';
import '../browser/services/browser_node_link_parser.dart';
import '../browser/services/browser_proxy_status_monitor.dart';
import '../browser/services/browser_proxy_node_controller.dart';
import '../browser/services/browser_proxy_form_mutator.dart';
import '../browser/services/browser_settings_action_handler.dart';
import '../browser/services/browser_settings_form_controller.dart';
import '../features/proxy/infrastructure/proxy_latency_probe.dart';
import '../browser/services/browser_settings_runtime_service.dart';
import '../browser/services/browser_runtime_coordinator.dart';
import '../browser/services/browser_shared_services.dart';
import '../browser/widgets/settings/clear_browsing_data_dialog.dart';
import '../browser/widgets/settings/general_settings_section.dart';
import '../browser/widgets/settings/local_http_settings_section.dart';
import '../browser/widgets/settings/settings_section_widgets.dart';
import '../browser/widgets/settings/video_settings_section.dart';
import '../services/app_toast.dart';
import 'settings_page_body.dart';
import 'browser_history_page.dart';
import 'data_management_page.dart';
import 'settings_page_result.dart';

enum SettingsInitialSection { home, localHttp }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.initialSection = SettingsInitialSection.home,
  });

  final SettingsInitialSection initialSection;

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
  final BrowserProxyFormMutator _proxyFormMutator =
      const BrowserProxyFormMutator();
  late final BrowserProxyNodeController _proxyNodeController;

  bool _proxySupported = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isClearingAppCache = false;
  bool _isTestingNodeSpeed = false;
  bool _hasAppliedChanges = false;
  DataManagementPageResult? _dataManagementResult;
  String? _errorMessage;
  VoidCallback? _cancelNodeSpeedTest;
  ProxyState get _proxyState => _statusMonitor.proxyState.value;
  LocalHttpFileServerState get _localHttpState =>
      _statusMonitor.localHttpState.value;

  @override
  void initState() {
    super.initState();
    _nodeLinkParser = BrowserNodeLinkParser(
      subscriptionService: _subscriptionService,
    );
    _proxyNodeController = BrowserProxyNodeController(
      formController: _formController,
    );
    _settingsActionHandler = BrowserSettingsActionHandler();
    _runtimeService = BrowserSettingsRuntimeService(
      saveSettings: _settingsService.saveSettings,
      applyProxy: BrowserRuntimeCoordinator.instance.applyProxySettings,
      clearProxy: BrowserRuntimeCoordinator.instance.clearProxySettings,
      applyLocalHttpSettings:
          BrowserRuntimeCoordinator.instance.applyLocalHttpSettings,
      stopLocalHttpServer: BrowserRuntimeCoordinator.instance.stopLocalHttp,
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
    _cancelNodeSpeedTest?.call();
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

  Future<void> _openBrowserHistory() async {
    final result = await Navigator.of(context).pushNamed('/browser-history');
    if (!mounted || result is! BrowserHistoryPageResult) {
      return;
    }
    Navigator.of(context).pop(
      SettingsPageResult(
        settingsChanged: _hasAppliedChanges,
        openHistoryUrl: result.url,
        dataManagementResult: _dataManagementResult,
      ),
    );
  }

  Future<void> _openDataManagement() async {
    final result = await Navigator.of(context).pushNamed('/data-management');
    if (!mounted || result is! DataManagementPageResult || !result.changed) {
      return;
    }
    _dataManagementResult = _mergeDataManagementResults(
      _dataManagementResult,
      result,
    );
    _hasAppliedChanges = _hasAppliedChanges || result.settingsChanged;
    await _loadSettings();
  }

  DataManagementPageResult _mergeDataManagementResults(
    DataManagementPageResult? previous,
    DataManagementPageResult current,
  ) {
    if (previous == null) return current;
    return DataManagementPageResult(
      changed: previous.changed || current.changed,
      favoritesChanged: previous.favoritesChanged || current.favoritesChanged,
      settingsChanged: previous.settingsChanged || current.settingsChanged,
      webDataChanged: previous.webDataChanged || current.webDataChanged,
      restoredOrigins: <String>{
        ...previous.restoredOrigins,
        ...current.restoredOrigins,
      }.toList(growable: false),
    );
  }

  SettingsPageResult _pageResult({
    bool? settingsChanged,
    String? openHistoryUrl,
  }) {
    return SettingsPageResult(
      settingsChanged: settingsChanged ?? _hasAppliedChanges,
      openHistoryUrl: openHistoryUrl,
      dataManagementResult: _dataManagementResult,
    );
  }

  void _closePage({bool? settingsChanged}) {
    Navigator.of(context).pop(_pageResult(settingsChanged: settingsChanged));
  }

  void _handleProxyFormChanged() {
    setState(_proxyNodeController.syncSelectedFromForm);
    _markSectionDirty();
  }

  void _addCurrentProxyNode({String? preferredName}) {
    BrowserProxyNode? node;
    setState(() {
      node = _proxyNodeController.addCurrent(preferredName: preferredName);
    });
    if (node == null) {
      _showSnackBar('请先填写节点地址和端口');
      return;
    }
    _markSectionDirty();
    _showSnackBar('已添加代理节点：${node!.name}');
  }

  void _selectProxyNode(String nodeId) {
    setState(() => _proxyNodeController.select(nodeId));
    _markSectionDirty();
  }

  void _deleteProxyNode(String nodeId) {
    setState(() => _proxyNodeController.delete(nodeId));
    _markSectionDirty();
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
        _proxyNodeController.appendParsedSettings(
          settings: result.settings,
          name: result.node.name,
        );
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
    if (_isTestingNodeSpeed) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _isTestingNodeSpeed = true;
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

      final operation = _proxyService.startNodeLatencyTest(
        settings.proxyConfiguration,
      );
      _cancelNodeSpeedTest = operation.cancel;
      final latency = await operation.result;
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
    } on ProxyLatencyTestCanceledException {
      _showSnackBar('已关闭测速');
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
          _isTestingNodeSpeed = false;
        });
        _markSectionDirty();
      }
      _cancelNodeSpeedTest = null;
    }
  }

  void _cancelTestNodeSpeed() {
    _cancelNodeSpeedTest?.call();
  }

  BrowserSettings _buildSettingsFromForm() {
    return _proxyNodeController.buildSettings();
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
        _closePage(settingsChanged: true);
      }
    } catch (error) {
      _showSnackBar(_proxyService.describeError(error));
      if (!mounted) {
        return;
      }
      if (closeAfterSave) {
        _closePage(settingsChanged: true);
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

  Future<void> _clearAppCache() async {
    if (_isClearingAppCache) {
      return;
    }

    setState(() {
      _isClearingAppCache = true;
    });
    _markSectionDirty();

    try {
      await _settingsActionHandler.clearAppCache();
      _showSnackBar('已清理应用缓存');
    } catch (error) {
      _showSnackBar('清理应用缓存失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isClearingAppCache = false;
        });
        _markSectionDirty();
      }
    }
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
      desktopUserAgentController: _formController.desktopUserAgentController,
      openNewWindowInTab: _formController.openNewWindowInTab,
      appCacheAutoClearEnabled: _formController.appCacheAutoClearEnabled,
      appCacheAutoClearIntervalHours:
          _formController.appCacheAutoClearIntervalHours,
      isClearingAppCache: _isClearingAppCache,
      onHomepageChanged: (_) => _markSectionDirty(),
      onDesktopUserAgentChanged: (_) => _markSectionDirty(),
      onOpenNewWindowInTabChanged: (value) {
        setState(() {
          _formController.openNewWindowInTab = value;
        });
        _markSectionDirty();
      },
      onClearBrowsingDataTap: _showClearBrowsingDataDialog,
      onClearAppCacheTap: _clearAppCache,
      onAppCacheAutoClearChanged: (value) {
        setState(() {
          _formController.appCacheAutoClearEnabled = value;
        });
        _markSectionDirty();
      },
      onAppCacheAutoClearIntervalChanged: (value) {
        setState(() {
          _formController.appCacheAutoClearIntervalHours = value;
        });
        _markSectionDirty();
      },
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

  Widget _buildLocalHttpSection(BuildContext context) {
    return LocalHttpSettingsSection(
      enabled: _formController.localHttpServerEnabled,
      stateLabel: _localHttpStateLabel,
      stateColor: _localHttpStateColor(Theme.of(context).colorScheme),
      portText:
          '监听端口：${_localHttpFileServerService.boundPort?.toString() ?? '未启动'}',
      baseUrlText: _localHttpFileServerService.baseUrl == null
          ? null
          : '访问地址：${_localHttpFileServerService.baseUrl}',
      lanUrls: _localHttpFileServerService.lanUrls,
      bindAllInterfaces: _formController.localHttpBindAllInterfaces,
      rootPathController: _formController.localHttpRootPathController,
      portController: _formController.localHttpPortController,
      uploadKeyController: _formController.localHttpUploadKeyController,
      onToggle: _handleLocalHttpToggle,
      onUseSharedDownloadsDirectory: _useSharedDownloadsDirectory,
      onBindAllInterfacesChanged: _handleLocalHttpBindAllInterfacesChanged,
    );
  }

  void _handleProxyProtocolChanged(String value) {
    _applyProxyFormMutation(
      () => _proxyFormMutator.changeProtocol(_formController, value),
    );
  }

  void _handleProxyTlsEnabledChanged(bool value) {
    _applyProxyFormMutation(
      () => _proxyFormMutator.setTlsEnabled(_formController, value),
    );
  }

  void _handleProxyTransportTypeChanged(String value) {
    _applyProxyFormMutation(
      () => _proxyFormMutator.setTransportType(_formController, value),
    );
  }

  void _handleProxyPacketEncodingChanged(String value) {
    _applyProxyFormMutation(
      () => _proxyFormMutator.setPacketEncoding(_formController, value),
    );
  }

  void _handleProxyTlsInsecureChanged(bool value) {
    _applyProxyFormMutation(
      () => _proxyFormMutator.setTlsInsecure(_formController, value),
    );
  }

  void _applyProxyFormMutation(VoidCallback mutation) {
    setState(mutation);
    _proxyNodeController.syncSelectedFromForm();
    _markSectionDirty();
  }

  void _handleLocalHttpToggle(bool value) {
    setState(() {
      _formController.localHttpServerEnabled = value;
    });
    _markSectionDirty();
  }

  void _handleLocalHttpBindAllInterfacesChanged(bool value) {
    setState(() {
      _formController.localHttpBindAllInterfaces = value;
    });
    _markSectionDirty();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialSection == SettingsInitialSection.localHttp) {
      if (_isLoading) {
        return Scaffold(
          appBar: AppBar(title: const Text('本地 HTTP 文件服务')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return SettingsSectionPage(
        title: '本地 HTTP 文件服务',
        icon: Icons.folder_shared_outlined,
        revisionListenable: _formController.revision,
        isSavingBuilder: () => _isSaving,
        buildChildren: (sectionContext) => [
          _buildLocalHttpSection(sectionContext),
        ],
        onSave: () => _saveSettings(closeAfterSave: false),
      );
    }
    return SettingsPageScaffold(
      isLoading: _isLoading,
      isSaving: _isSaving,
      onClose: _closePage,
      onSave: _saveSettings,
      body: SettingsPageBody(
        isLoading: _isLoading,
        buildGeneralSection: _buildGeneralSection,
        buildVideoSection: _buildVideoSection,
        pushSection: _pushSection,
        onOpenBrowserHistory: _openBrowserHistory,
        onOpenDataManagement: _openDataManagement,
        formController: _formController,
        proxySupported: _proxySupported,
        isSaving: _isSaving,
        isTestingNodeSpeed: _isTestingNodeSpeed,
        proxyStateLabel: _proxyStateLabel,
        proxyStateColor: _proxyStateColor,
        proxyService: _proxyService,
        errorMessage: _errorMessage,
        onHandleProxyToggle: _handleProxyToggle,
        onParseNodeLink: _parseNodeLink,
        onTestNodeSpeed: _testNodeSpeed,
        onCancelTestSpeed: _cancelTestNodeSpeed,
        onAddProxyNode: _addCurrentProxyNode,
        onSelectProxyNode: _selectProxyNode,
        onDeleteProxyNode: _deleteProxyNode,
        onProxyConfigurationChanged: _handleProxyFormChanged,
        onProxyProtocolChanged: _handleProxyProtocolChanged,
        onProxyTlsEnabledChanged: _handleProxyTlsEnabledChanged,
        onProxyTransportTypeChanged: _handleProxyTransportTypeChanged,
        onProxyPacketEncodingChanged: _handleProxyPacketEncodingChanged,
        onProxyTlsInsecureChanged: _handleProxyTlsInsecureChanged,
      ),
    );
  }
}
