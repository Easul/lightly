enum OptionalFeatureId {
  telegram('telegram'),
  webRtcVoice('webrtc_voice'),
  easyTier('easytier'),
  lifeRuntime('life_runtime');

  const OptionalFeatureId(this.wireName);

  final String wireName;
}

class OptionalFeatureDescriptor {
  const OptionalFeatureDescriptor({
    required this.id,
    required this.displayName,
    required this.packageName,
    required this.minimumApiVersion,
  });

  final OptionalFeatureId id;
  final String displayName;
  final String packageName;
  final int minimumApiVersion;
}

class OptionalFeatureCatalog {
  const OptionalFeatureCatalog._();

  static const String manifestAsset = 'assets/optional_plugins/plugins.json';

  static const Map<OptionalFeatureId, OptionalFeatureDescriptor> descriptors =
      <OptionalFeatureId, OptionalFeatureDescriptor>{
        OptionalFeatureId.telegram: OptionalFeatureDescriptor(
          id: OptionalFeatureId.telegram,
          displayName: 'TG 工具插件',
          packageName: 'lightly.tool.plugin.telegram',
          minimumApiVersion: 3,
        ),
        OptionalFeatureId.webRtcVoice: OptionalFeatureDescriptor(
          id: OptionalFeatureId.webRtcVoice,
          displayName: '远程语音插件',
          packageName: 'lightly.tool.plugin.webrtc',
          minimumApiVersion: 3,
        ),
        OptionalFeatureId.easyTier: OptionalFeatureDescriptor(
          id: OptionalFeatureId.easyTier,
          displayName: 'EasyTier 插件',
          packageName: 'lightly.tool.plugin.easytier',
          minimumApiVersion: 2,
        ),
        OptionalFeatureId.lifeRuntime: OptionalFeatureDescriptor(
          id: OptionalFeatureId.lifeRuntime,
          displayName: '人生知识库运行时',
          packageName: 'lightly.tool.plugin.liferuntime',
          minimumApiVersion: 1,
        ),
      };

  static OptionalFeatureDescriptor descriptor(OptionalFeatureId id) {
    return descriptors[id]!;
  }
}
