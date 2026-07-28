class OptionalPluginStatus {
  const OptionalPluginStatus({
    required this.installed,
    required this.trusted,
    required this.enabled,
    this.versionCode,
    this.versionName,
    this.apiVersion,
    this.featureId,
  });

  final bool installed;
  final bool trusted;
  final bool enabled;
  final int? versionCode;
  final String? versionName;
  final int? apiVersion;
  final String? featureId;

  bool supportsApi(int minimumApiVersion) {
    return installed &&
        trusted &&
        enabled &&
        (apiVersion ?? 0) >= minimumApiVersion;
  }

  factory OptionalPluginStatus.fromMap(Map<Object?, Object?> map) {
    return OptionalPluginStatus(
      installed: map['installed'] == true,
      trusted: map['trusted'] == true,
      enabled: map['enabled'] != false,
      versionCode: (map['versionCode'] as num?)?.toInt(),
      versionName: map['versionName'] as String?,
      apiVersion: (map['apiVersion'] as num?)?.toInt(),
      featureId: map['featureId'] as String?,
    );
  }
}

enum OptionalPluginInstallResult {
  started,
  permissionRequired,
  invalidPackage,
  signatureMismatch,
  fileMissing,
  rejected;

  factory OptionalPluginInstallResult.fromWireValue(String? value) {
    return switch (value) {
      'started' => started,
      'permission_required' => permissionRequired,
      'invalid_package' => invalidPackage,
      'signature_mismatch' => signatureMismatch,
      'file_missing' => fileMissing,
      _ => rejected,
    };
  }
}
