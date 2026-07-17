import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../browser/services/browser_backup_service.dart';
import '../services/app_log_service.dart';
import '../services/app_toast.dart';
import '../services/shared_downloads_directory_service.dart';
import '../widgets/shared_download_access_dialog.dart';
import 'data_management_page_sections.dart';

class DataManagementPageResult {
  const DataManagementPageResult({
    required this.changed,
    required this.favoritesChanged,
    required this.settingsChanged,
    required this.webDataChanged,
    required this.restoredOrigins,
  });

  final bool changed;
  final bool favoritesChanged;
  final bool settingsChanged;
  final bool webDataChanged;
  final List<String> restoredOrigins;
}

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  final BrowserBackupService _backupService = BrowserBackupService();
  final AppLogService _appLogService = AppLogService.instance;
  final SharedDownloadsDirectoryService _sharedDownloadsDirectoryService =
      SharedDownloadsDirectoryService();
  bool _busy = false;
  bool _logRecordingEnabled = false;
  DataManagementPageResult? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogRecordingState());
  }

  Future<void> _loadLogRecordingState() async {
    await _appLogService.initialize();
    if (!mounted) {
      return;
    }
    setState(() {
      _logRecordingEnabled = _appLogService.isEnabled;
    });
  }

  Future<void> _closePage() async {
    if (!mounted || _busy) {
      return;
    }
    Navigator.pop(context, _result);
  }

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  Future<void> _exportToClipboard() async {
    setState(() => _busy = true);
    try {
      await _backupService.copyToClipboard();
      if (!mounted) return;
      _showToast('备份数据已复制到剪贴板');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportToDownloads() async {
    setState(() => _busy = true);
    try {
      final requestSharedAccessIfNeeded =
          await _shouldRequestSharedDownloadPermission(actionLabel: '备份文件');
      if (requestSharedAccessIfNeeded == null) {
        return;
      }
      final file = await _backupService.exportToDownloads(
        requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      );
      if (!mounted) return;
      _showToast('已导出到 ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _showToast('导出备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromFile() async {
    bool mergeFavorites = true;
    bool importSettings = true;
    bool importHistory = true;
    bool importClipboard = true;
    bool importCalculatorHistory = true;
    bool importWebData = true;
    bool importEasyTierProfiles = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('导入数据'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('请选择备份文件后导入，并勾选要恢复的数据类型。'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('合并收藏'),
                  value: mergeFavorites,
                  onChanged: (value) => setDialogState(() {
                    mergeFavorites = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入设置'),
                  subtitle: const Text('包含 TG 签到的 API、手机号、目标与命令配置'),
                  value: importSettings,
                  onChanged: (value) => setDialogState(() {
                    importSettings = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入浏览历史'),
                  value: importHistory,
                  onChanged: (value) => setDialogState(() {
                    importHistory = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入剪贴板内容与端口'),
                  value: importClipboard,
                  onChanged: (value) => setDialogState(() {
                    importClipboard = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入计算器历史'),
                  value: importCalculatorHistory,
                  onChanged: (value) => setDialogState(() {
                    importCalculatorHistory = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入登录数据 (Cookie 与站点存储)'),
                  subtitle: const Text('恢复大多数网站的登录状态，包括 Cookie 与 localStorage'),
                  value: importWebData,
                  onChanged: (value) => setDialogState(() {
                    importWebData = value ?? true;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入 VPN 配置'),
                  subtitle: const Text('恢复 EasyTier 网络档案与当前选中的网络'),
                  value: importEasyTierProfiles,
                  onChanged: (value) => setDialogState(() {
                    importEasyTierProfiles = value ?? true;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final filePath = picked != null && picked.files.isNotEmpty
        ? picked.files.first.path
        : null;
    if (filePath == null || filePath.isEmpty) {
      if (mounted) {
        _showToast('未选择备份文件');
      }
      return;
    }

    final jsonText = await File(filePath).readAsString();

    final validationError = _backupService.validateImportJson(jsonText);
    if (validationError != null) {
      if (mounted) {
        _showToast(validationError);
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final data = await _backupService.importFromJson(jsonText);
      final result = await _backupService.importData(
        data,
        mergeFavorites: mergeFavorites,
        importSettings: importSettings,
        importHistory: importHistory,
        importClipboard: importClipboard,
        importCalculatorHistory: importCalculatorHistory,
        importWebData: importWebData,
        importEasyTierProfiles: importEasyTierProfiles,
      );
      _result = DataManagementPageResult(
        changed: true,
        favoritesChanged: result.favoritesImported > 0,
        settingsChanged: importSettings,
        webDataChanged:
            result.cookiesImported > 0 || result.webStorageImported > 0,
        restoredOrigins: result.restoredOrigins,
      );
      if (!mounted) return;
      _showToast('导入完成：$result');
    } catch (e) {
      if (!mounted) return;
      _showToast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportLogsToDownloads() async {
    setState(() => _busy = true);
    try {
      final requestSharedAccessIfNeeded =
          await _shouldRequestSharedDownloadPermission(actionLabel: '运行日志');
      if (requestSharedAccessIfNeeded == null) {
        return;
      }
      final file = await _appLogService.exportLogToDownloads(
        requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
      );
      if (!mounted) return;
      _showToast('日志已导出到 ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _showToast('导出日志失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _shouldRequestSharedDownloadPermission({
    required String actionLabel,
  }) async {
    if (!Platform.isAndroid) {
      return true;
    }

    final hasPermission = await _sharedDownloadsDirectoryService
        .hasFileAccessPermission();
    if (hasPermission) {
      return true;
    }
    if (!mounted) {
      return null;
    }

    final choice = await showSharedDownloadAccessDialog(
      context,
      actionLabel: actionLabel,
    );
    switch (choice) {
      case SharedDownloadAccessChoice.requestPermission:
        final granted = await _sharedDownloadsDirectoryService
            .requestFileAccessPermission();
        if (!granted && mounted) {
          _showToast('未获得 Download 授权，将保存到应用目录');
        }
        return granted;
      case SharedDownloadAccessChoice.useAppDirectory:
        if (mounted) {
          _showToast('已改为保存到应用目录');
        }
        return false;
      case SharedDownloadAccessChoice.cancel:
        return null;
    }
  }

  Future<void> _copyLogsToClipboard() async {
    setState(() => _busy = true);
    try {
      await _appLogService.copyLogToClipboard();
      if (!mounted) return;
      _showToast('运行日志已复制到剪贴板');
    } catch (e) {
      if (!mounted) return;
      _showToast('复制日志失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLogRecordingEnabled(bool enabled) async {
    setState(() => _busy = true);
    try {
      await _appLogService.setEnabled(enabled);
      if (!mounted) {
        return;
      }
      setState(() {
        _logRecordingEnabled = enabled;
      });
      _showToast(enabled ? '已开启运行日志记录' : '已关闭运行日志记录');
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showToast('切换日志记录失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _busy) {
          return;
        }
        await _closePage();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('数据管理'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _closePage,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DataExportSection(
                busy: _busy,
                onExportToDownloads: () => unawaited(_exportToDownloads()),
                onExportToClipboard: () => unawaited(_exportToClipboard()),
              ),
              const SizedBox(height: 24),
              DataLogSection(
                busy: _busy,
                logRecordingEnabled: _logRecordingEnabled,
                logPath: _appLogService.logPath,
                onSetLogRecordingEnabled: (enabled) =>
                    unawaited(_setLogRecordingEnabled(enabled)),
                onExportLogsToDownloads: () =>
                    unawaited(_exportLogsToDownloads()),
                onCopyLogsToClipboard: () => unawaited(_copyLogsToClipboard()),
              ),
              const SizedBox(height: 24),
              DataImportSection(
                busy: _busy,
                onImportFromFile: () => unawaited(_importFromFile()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
