class SettingsPageResult {
  const SettingsPageResult({
    required this.settingsChanged,
    this.openHistoryUrl,
  });

  final bool settingsChanged;
  final String? openHistoryUrl;
}
