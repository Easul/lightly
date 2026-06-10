import 'dart:convert';

import '../../calculator/calculation_history.dart';
import '../../models/easytier_network_profile.dart';
import '../browser_settings.dart';
import '../models/browser_favorite.dart';
import '../models/browser_history_entry.dart';

class BrowserBackupData {
  const BrowserBackupData({
    required this.favorites,
    required this.settings,
    required this.history,
    required this.calculatorHistory,
    required this.clipboardContent,
    required this.clipboardPort,
    required this.cookies,
    required this.webStorage,
    required this.easyTierProfiles,
    required this.selectedEasyTierProfileId,
    required this.exportedAt,
  });

  final List<BrowserFavorite> favorites;
  final BrowserSettings settings;
  final List<BrowserHistoryEntry> history;
  final List<CalculationHistory> calculatorHistory;
  final String clipboardContent;
  final int? clipboardPort;
  final List<Map<String, dynamic>> cookies;
  final List<Map<String, dynamic>> webStorage;
  final List<EasyTierNetworkProfile> easyTierProfiles;
  final String? selectedEasyTierProfileId;
  final DateTime exportedAt;

  Map<String, dynamic> toJson() {
    return {
      'version': 7,
      'exportedAt': exportedAt.toIso8601String(),
      'favorites': favorites.map((f) => f.toMap()).toList(),
      'settings': settings.toJson(),
      'history': history.map((h) => h.toMap()).toList(),
      'calculatorHistory': calculatorHistory.map((h) => h.toJson()).toList(),
      'clipboardContent': clipboardContent,
      'clipboardPort': clipboardPort,
      'cookies': cookies,
      'webStorage': webStorage,
      'easyTierProfiles': easyTierProfiles
          .map((profile) => profile.toJson())
          .toList(),
      'selectedEasyTierProfileId': selectedEasyTierProfileId,
    };
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory BrowserBackupData.fromJsonString(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final favorites = (decoded['favorites'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              BrowserFavorite.fromMap(Map<String, Object?>.from(item as Map)),
        )
        .toList();
    final settings = BrowserSettings.fromJson(
      Map<String, dynamic>.from(decoded['settings'] as Map? ?? const {}),
    );
    final history = (decoded['history'] as List<dynamic>? ?? const [])
        .map(
          (item) => BrowserHistoryEntry.fromMap(
            Map<String, Object?>.from(item as Map),
          ),
        )
        .toList();
    final calculatorHistory =
        (decoded['calculatorHistory'] as List<dynamic>? ?? const [])
            .map(
              (item) => CalculationHistory.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final cookies = (decoded['cookies'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final webStorage = (decoded['webStorage'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final easyTierProfiles =
        (decoded['easyTierProfiles'] as List<dynamic>? ?? const [])
            .map(
              (item) => EasyTierNetworkProfile.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    return BrowserBackupData(
      favorites: favorites,
      settings: settings,
      history: history,
      calculatorHistory: calculatorHistory,
      clipboardContent: decoded['clipboardContent'] as String? ?? '',
      clipboardPort: (decoded['clipboardPort'] as num?)?.toInt(),
      cookies: cookies,
      webStorage: webStorage,
      easyTierProfiles: easyTierProfiles,
      selectedEasyTierProfileId:
          decoded['selectedEasyTierProfileId'] as String?,
      exportedAt:
          DateTime.tryParse(decoded['exportedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ImportResult {
  const ImportResult({
    required this.favoritesImported,
    required this.historyImported,
    required this.calculatorImported,
    required this.cookiesImported,
    required this.webStorageImported,
    required this.easyTierProfilesImported,
    required this.settingsUpdated,
    required this.clipboardUpdated,
    required this.restoredOrigins,
  });

  final int favoritesImported;
  final int historyImported;
  final int calculatorImported;
  final int cookiesImported;
  final int webStorageImported;
  final int easyTierProfilesImported;
  final bool settingsUpdated;
  final bool clipboardUpdated;
  final List<String> restoredOrigins;

  @override
  String toString() {
    final parts = <String>[
      if (favoritesImported > 0) '$favoritesImported 个收藏',
      if (historyImported > 0) '$historyImported 条浏览历史',
      if (calculatorImported > 0) '$calculatorImported 条计算器历史',
      if (cookiesImported > 0) '$cookiesImported 个 Cookie',
      if (webStorageImported > 0) '$webStorageImported 个站点存储',
      if (easyTierProfilesImported > 0) '$easyTierProfilesImported 个 VPN 配置',
      if (settingsUpdated) '设置',
      if (clipboardUpdated) '剪贴板',
    ];
    return parts.isEmpty ? '无数据更新' : parts.join('、');
  }
}
