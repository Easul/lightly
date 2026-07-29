import 'package:package_info_plus/package_info_plus.dart';

import '../browser/browser_settings_service.dart';
import '../features/optional_plugins/domain/optional_feature.dart';
import '../features/optional_plugins/domain/optional_plugin_download_settings.dart';
import '../features/optional_plugins/domain/optional_plugin_manifest.dart';
import '../features/optional_plugins/domain/optional_plugin_status.dart';
import '../features/optional_plugins/infrastructure/optional_plugin_download_settings_store.dart';
import '../features/optional_plugins/infrastructure/optional_plugin_manifest_loader.dart';
import '../features/optional_plugins/infrastructure/optional_plugin_platform_gateway.dart';
import '../features/optional_plugins/infrastructure/optional_plugin_repository.dart';
import '../features/proxy/infrastructure/proxy_service.dart';

class OptionalFeatureUnavailableException implements Exception {
  const OptionalFeatureUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef OptionalPluginRepositoryFactory =
    OptionalPluginRepository Function({
      required OptionalPluginProxyResolver proxyResolver,
      required OptionalPluginDownloadSettings downloadSettings,
      required bool proxyAvailable,
    });

class OptionalFeatureCoordinator {
  OptionalFeatureCoordinator({
    BrowserSettingsService? settingsService,
    ProxyService? proxyService,
    OptionalPluginDownloadSettingsStore? downloadSettingsStore,
    OptionalPluginPlatformGateway? platformGateway,
    OptionalPluginRepositoryFactory? repositoryFactory,
    Future<PackageInfo> Function()? loadPackageInfo,
  }) : _settingsService = settingsService ?? BrowserSettingsService(),
       _proxyService = proxyService ?? ProxyService(),
       _downloadSettingsStore =
           downloadSettingsStore ?? OptionalPluginDownloadSettingsStore(),
       _platformGateway =
           platformGateway ?? OptionalPluginPlatformGateway.instance,
       _repositoryFactory =
           repositoryFactory ??
           (({
             required proxyResolver,
             required downloadSettings,
             required proxyAvailable,
           }) => OptionalPluginRepository(
             proxyResolver: proxyResolver,
             downloadSettings: downloadSettings,
             proxyAvailable: proxyAvailable,
           )),
       _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform;

  static final OptionalFeatureCoordinator instance =
      OptionalFeatureCoordinator();

  final BrowserSettingsService _settingsService;
  final ProxyService _proxyService;
  final OptionalPluginDownloadSettingsStore _downloadSettingsStore;
  final OptionalPluginPlatformGateway _platformGateway;
  final OptionalPluginRepositoryFactory _repositoryFactory;
  final Future<PackageInfo> Function() _loadPackageInfo;

  Future<OptionalPluginStatus> getStatus(OptionalFeatureId featureId) {
    final descriptor = OptionalFeatureCatalog.descriptor(featureId);
    return _platformGateway.getStatus(descriptor.packageName);
  }

  Future<bool> isAvailable(OptionalFeatureId featureId) async {
    final descriptor = OptionalFeatureCatalog.descriptor(featureId);
    final status = await getStatus(featureId);
    return status.featureId == featureId.wireName &&
        status.supportsApi(descriptor.minimumApiVersion);
  }

  Future<OptionalPluginInstallResult> downloadAndInstall(
    OptionalFeatureId featureId, {
    OptionalPluginDownloadProgress? onProgress,
  }) async {
    final descriptor = OptionalFeatureCatalog.descriptor(featureId);
    final abi = await _platformGateway.getSupportedAbi();
    if (abi == null) {
      throw const OptionalFeatureUnavailableException('当前设备 ABI 不受支持');
    }
    final repository = await _createRepository();
    final manifest = await repository.loadManifest();
    final release = manifest.releaseFor(featureId);
    if (release == null || release.packageName != descriptor.packageName) {
      throw const OptionalFeatureUnavailableException('插件发布清单缺少对应功能');
    }
    if (release.apiVersion < descriptor.minimumApiVersion) {
      throw const OptionalFeatureUnavailableException('插件接口版本过低');
    }
    final currentVersionCode = _parseVersionCode(
      (await _loadPackageInfo()).buildNumber,
    );
    if (currentVersionCode < release.minimumLightlyVersionCode) {
      throw const OptionalFeatureUnavailableException('请先升级 Lightly 再安装插件');
    }
    final artifact = release.artifactForAbi(abi);
    if (artifact == null) {
      throw OptionalFeatureUnavailableException('插件没有提供 $abi 安装包');
    }
    final apk = await repository.downloadArtifact(
      descriptor,
      release,
      artifact,
      onProgress: onProgress,
    );
    return _platformGateway.installApk(
      path: apk.path,
      expectedPackageName: descriptor.packageName,
    );
  }

  Future<OptionalPluginConnectionTestResult> testDownloadRoute() async {
    final abi = await _platformGateway.getSupportedAbi();
    if (abi == null) {
      throw const OptionalFeatureUnavailableException('当前设备 ABI 不受支持');
    }
    final repository = await _createRepository();
    final manifest = await repository.loadManifest();
    for (final featureId in OptionalFeatureId.values) {
      final artifact = manifest.releaseFor(featureId)?.artifactForAbi(abi);
      if (artifact != null) {
        return repository.testArtifact(artifact);
      }
    }
    throw const OptionalFeatureUnavailableException('包内插件清单没有当前 ABI 的测试地址');
  }

  Future<OptionalPluginManifest> loadBundledManifest() async {
    return OptionalPluginManifestLoader().load();
  }

  Future<OptionalPluginRepository> _createRepository() async {
    final browserSettings = await _settingsService.loadSettings();
    final proxyConfiguration = browserSettings.proxyConfiguration;
    final downloadSettings = await _downloadSettingsStore.load();
    var proxyAvailable = false;
    if (downloadSettings.mode != OptionalPluginDownloadMode.mirrorOnly &&
        proxyConfiguration.shouldApplyProxy) {
      try {
        await _proxyService.applyProxy(proxyConfiguration);
        proxyAvailable = true;
      } catch (_) {
        proxyAvailable = false;
      }
    }
    return _repositoryFactory(
      proxyResolver: (uri) =>
          _proxyService.findProxyForDownload(proxyConfiguration, uri),
      downloadSettings: downloadSettings,
      proxyAvailable: proxyAvailable,
    );
  }

  Future<void> openInstallPermissionSettings() {
    return _platformGateway.openInstallPermissionSettings();
  }

  int _parseVersionCode(String value) {
    return int.tryParse(value.trim()) ?? 0;
  }
}
