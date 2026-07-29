enum OptionalPluginDownloadMode {
  automatic('automatic'),
  githubOnly('github_only'),
  mirrorOnly('mirror_only');

  const OptionalPluginDownloadMode(this.wireName);

  final String wireName;

  static OptionalPluginDownloadMode fromWireName(String? value) {
    return values.firstWhere(
      (mode) => mode.wireName == value,
      orElse: () => OptionalPluginDownloadMode.automatic,
    );
  }
}

class OptionalPluginDownloadSettings {
  const OptionalPluginDownloadSettings({
    this.mode = OptionalPluginDownloadMode.automatic,
    this.mirrorPrefix = defaultMirrorPrefix,
  });

  static const String defaultMirrorPrefix = 'https://ghfast.top/';

  final OptionalPluginDownloadMode mode;
  final String mirrorPrefix;

  OptionalPluginDownloadSettings copyWith({
    OptionalPluginDownloadMode? mode,
    String? mirrorPrefix,
  }) {
    return OptionalPluginDownloadSettings(
      mode: mode ?? this.mode,
      mirrorPrefix: mirrorPrefix ?? this.mirrorPrefix,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wireName,
    'mirrorPrefix': normalizedMirrorPrefix,
  };

  factory OptionalPluginDownloadSettings.fromJson(Map<String, Object?> json) {
    final settings = OptionalPluginDownloadSettings(
      mode: OptionalPluginDownloadMode.fromWireName(json['mode'] as String?),
      mirrorPrefix: json['mirrorPrefix'] as String? ?? defaultMirrorPrefix,
    );
    return settings.copyWith(mirrorPrefix: settings.normalizedMirrorPrefix);
  }

  String get normalizedMirrorPrefix {
    final value = mirrorPrefix.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return defaultMirrorPrefix;
    }
    return value.endsWith('/') ? value : '$value/';
  }

  String? get validationError {
    final value = mirrorPrefix.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return '镜像前缀必须是有效的 HTTPS 地址';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return '镜像前缀不能包含查询参数或片段';
    }
    return null;
  }

  Uri mirrorUri(Uri source) {
    return Uri.parse('$normalizedMirrorPrefix$source');
  }
}
