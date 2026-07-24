import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_toast.dart';
import '../services/app_version_info.dart';
import '../theme/app_theme.dart';

/// 版本页：寄语 + 版本号（含 commit），复用全局分节样式排版。
class AboutVersionPage extends StatefulWidget {
  const AboutVersionPage({super.key});

  @override
  State<AboutVersionPage> createState() => _AboutVersionPageState();
}

class _AboutVersionPageState extends State<AboutVersionPage> {
  AppVersionInfo? _versionInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionInfo = AppVersionInfo(packageInfo: packageInfo);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionInfo = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _copyVersion(String version) async {
    await Clipboard.setData(ClipboardData(text: version));
    await AppToast.show('已复制版本号');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final versionText = _isLoading
        ? '加载中…'
        : (_versionInfo?.displayVersion ?? '未知');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('版本'),
      ),
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.35),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '若轻',
                  style: textTheme.headlineSmall?.copyWith(
                    fontSize: 30,
                    letterSpacing: 6,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '简约而不简单',
                  style: textTheme.bodyMedium?.copyWith(
                    letterSpacing: 2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  width: 32,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 30),
                InkWell(
                  onTap: _isLoading ? null : () => _copyVersion(versionText),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          versionText,
                          style: textTheme.bodyLarge?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.copy_rounded,
                          size: 15,
                          color: AppColors.iconTint,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
