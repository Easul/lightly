import 'dart:convert';

import 'optional_feature.dart';

class OptionalPluginArtifact {
  const OptionalPluginArtifact({
    required this.url,
    required this.sha256,
    required this.size,
  });

  final Uri url;
  final String sha256;
  final int size;

  factory OptionalPluginArtifact.fromJson(Map<String, dynamic> json) {
    final url = Uri.tryParse(json['url'] as String? ?? '');
    final digest = (json['sha256'] as String? ?? '').trim().toLowerCase();
    final size = (json['size'] as num?)?.toInt() ?? 0;
    if (url == null ||
        url.scheme != 'https' ||
        digest.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        size <= 0) {
      throw const FormatException('Invalid optional plugin artifact');
    }
    return OptionalPluginArtifact(url: url, sha256: digest, size: size);
  }
}

class OptionalPluginRelease {
  const OptionalPluginRelease({
    required this.featureId,
    required this.packageName,
    required this.apiVersion,
    required this.versionCode,
    required this.versionName,
    required this.minimumLightlyVersionCode,
    required this.artifacts,
  });

  final OptionalFeatureId featureId;
  final String packageName;
  final int apiVersion;
  final int versionCode;
  final String versionName;
  final int minimumLightlyVersionCode;
  final Map<String, OptionalPluginArtifact> artifacts;

  OptionalPluginArtifact? artifactForAbi(String abi) => artifacts[abi];

  factory OptionalPluginRelease.fromJson(
    OptionalFeatureId featureId,
    Map<String, dynamic> json,
  ) {
    final artifactsJson = json['artifacts'] as Map<String, dynamic>?;
    if (artifactsJson == null) {
      throw const FormatException('Plugin artifacts are missing');
    }
    return OptionalPluginRelease(
      featureId: featureId,
      packageName: json['packageName'] as String? ?? '',
      apiVersion: (json['apiVersion'] as num?)?.toInt() ?? 0,
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      versionName: json['versionName'] as String? ?? '',
      minimumLightlyVersionCode:
          (json['minimumLightlyVersionCode'] as num?)?.toInt() ?? 0,
      artifacts: <String, OptionalPluginArtifact>{
        for (final entry in artifactsJson.entries)
          entry.key: OptionalPluginArtifact.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }
}

class OptionalPluginManifest {
  const OptionalPluginManifest({
    required this.schemaVersion,
    required this.releases,
  });

  final int schemaVersion;
  final Map<OptionalFeatureId, OptionalPluginRelease> releases;

  OptionalPluginRelease? releaseFor(OptionalFeatureId id) => releases[id];

  factory OptionalPluginManifest.parse(String source) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final schemaVersion = (decoded['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported optional plugin manifest schema: $schemaVersion',
      );
    }
    final plugins = decoded['plugins'] as Map<String, dynamic>?;
    if (plugins == null) {
      throw const FormatException('Plugin manifest has no plugins');
    }
    final releases = <OptionalFeatureId, OptionalPluginRelease>{};
    for (final feature in OptionalFeatureId.values) {
      final raw = plugins[feature.wireName];
      if (raw is Map<String, dynamic>) {
        releases[feature] = OptionalPluginRelease.fromJson(feature, raw);
      }
    }
    return OptionalPluginManifest(
      schemaVersion: schemaVersion,
      releases: Map<OptionalFeatureId, OptionalPluginRelease>.unmodifiable(
        releases,
      ),
    );
  }
}
