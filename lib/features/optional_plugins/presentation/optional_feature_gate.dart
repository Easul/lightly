import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/optional_feature_coordinator.dart';
import '../../../services/app_toast.dart';
import '../domain/optional_feature.dart';
import '../domain/optional_plugin_status.dart';

class OptionalFeatureGate {
  OptionalFeatureGate({OptionalFeatureCoordinator? coordinator})
    : _coordinator = coordinator ?? OptionalFeatureCoordinator.instance;

  final OptionalFeatureCoordinator _coordinator;

  Future<bool> ensureAvailable(
    BuildContext context,
    OptionalFeatureId featureId,
  ) async {
    final descriptor = OptionalFeatureCatalog.descriptor(featureId);
    final status = await _coordinator.getStatus(featureId);
    if (!context.mounted) {
      return false;
    }
    if (status.featureId == featureId.wireName &&
        status.supportsApi(descriptor.minimumApiVersion)) {
      return true;
    }
    if (status.installed && !status.trusted) {
      await _showMessage(
        context,
        title: '插件签名不匹配',
        message: '${descriptor.displayName} 不是由当前 Lightly 签名发布，已拒绝加载。',
      );
      return false;
    }
    if (status.installed) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('插件版本不兼容'),
          content: Text('需要更新 ${descriptor.displayName} 后才能继续使用。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('下载更新'),
            ),
          ],
        ),
      );
      if (shouldUpdate != true || !context.mounted) {
        return false;
      }
      return _downloadAndInstall(context, featureId);
    }
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('安装${descriptor.displayName}'),
        content: const Text('该功能采用独立插件提供，需要通过已配置的代理从 GitHub 下载并安装。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('下载插件'),
          ),
        ],
      ),
    );
    if (shouldInstall != true || !context.mounted) {
      return false;
    }
    return _downloadAndInstall(context, featureId);
  }

  Future<bool> _downloadAndInstall(
    BuildContext context,
    OptionalFeatureId featureId,
  ) async {
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    var progressOpen = true;
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在下载插件'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, child) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 12),
                Text(
                  value == null ? '正在连接 GitHub…' : '${(value * 100).round()}%',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void> closeProgress() async {
      if (!progressOpen) {
        return;
      }
      progressOpen = false;
      if (navigator.mounted) {
        navigator.pop();
      }
      await progressDialog;
    }

    try {
      final result = await _coordinator.downloadAndInstall(
        featureId,
        onProgress: (received, total) {
          progress.value = total <= 0 ? null : received / total;
        },
      );
      await closeProgress();
      if (result == OptionalPluginInstallResult.permissionRequired) {
        await _coordinator.openInstallPermissionSettings();
        unawaited(AppToast.show('请允许 Lightly 安装未知应用，然后重新点击功能入口'));
        return false;
      }
      if (result != OptionalPluginInstallResult.started) {
        unawaited(AppToast.show(_installErrorMessage(result)));
        return false;
      }
      unawaited(AppToast.show('请在系统安装界面完成插件安装'));
      return false;
    } on OptionalFeatureProxyRequiredException {
      await closeProgress();
      if (context.mounted) {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('需要代理'),
            content: const Text('请先在设置中配置并启用代理，再下载插件。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('打开设置'),
              ),
            ],
          ),
        );
        if (openSettings == true && context.mounted) {
          await Navigator.pushNamed(context, '/settings');
        }
      }
      return false;
    } catch (error) {
      await closeProgress();
      unawaited(AppToast.show('插件下载安装失败：$error'));
      return false;
    } finally {
      await closeProgress();
      progress.dispose();
    }
  }

  String _installErrorMessage(OptionalPluginInstallResult result) {
    return switch (result) {
      OptionalPluginInstallResult.invalidPackage => '插件包名不匹配，已拒绝安装',
      OptionalPluginInstallResult.signatureMismatch => '插件签名不匹配，已拒绝安装',
      OptionalPluginInstallResult.fileMissing => '插件安装文件不存在',
      _ => '无法启动插件安装',
    };
  }

  Future<void> _showMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
