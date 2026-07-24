import 'package:package_info_plus/package_info_plus.dart';

/// 版本号约定：`v` + semver + `+` + 6 位 commit 号，例如 `v1.0.8+a39a9dc`。
///
/// 发布构建时 `versionName` 已被写成 `tag+commit`，这里只在缺失时兜底。
class AppVersionInfo {
  AppVersionInfo({required this.packageInfo});

  final PackageInfo packageInfo;

  /// 完整版本号（含 commit 号，可直接展示）。
  String get displayVersion {
    final version = packageInfo.version.trim();
    if (version.isEmpty) {
      return 'v${packageInfo.buildNumber}';
    }
    return version.startsWith('v') ? version : 'v$version';
  }

  /// 不含 commit 号的 semver 部分，例如 `1.0.8`。
  String get semanticVersion {
    final base = displayVersion.split('+').first;
    return base.startsWith('v') ? base.substring(1) : base;
  }

  /// 版本号里的 6 位 commit 号（`+` 之后部分），可能为空。
  String get commitHash {
    final plusIndex = displayVersion.indexOf('+');
    if (plusIndex < 0 || plusIndex == displayVersion.length - 1) {
      return '';
    }
    return displayVersion.substring(plusIndex + 1);
  }
}
