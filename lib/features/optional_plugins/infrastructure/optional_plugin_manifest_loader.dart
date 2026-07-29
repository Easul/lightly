import 'package:flutter/services.dart';

import '../domain/optional_feature.dart';
import '../domain/optional_plugin_manifest.dart';

typedef OptionalPluginManifestSourceLoader = Future<String> Function();

class OptionalPluginManifestLoader {
  OptionalPluginManifestLoader({
    AssetBundle? assetBundle,
    OptionalPluginManifestSourceLoader? sourceLoader,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _sourceLoader = sourceLoader;

  final AssetBundle _assetBundle;
  final OptionalPluginManifestSourceLoader? _sourceLoader;

  Future<OptionalPluginManifest> load() async {
    final source =
        await (_sourceLoader?.call() ??
            _assetBundle.loadString(OptionalFeatureCatalog.manifestAsset));
    return OptionalPluginManifest.parse(source);
  }
}
