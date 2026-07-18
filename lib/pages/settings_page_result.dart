import 'data_management_page.dart';

class SettingsPageResult {
  const SettingsPageResult({
    required this.settingsChanged,
    this.openHistoryUrl,
    this.dataManagementResult,
  });

  final bool settingsChanged;
  final String? openHistoryUrl;
  final DataManagementPageResult? dataManagementResult;
}
