import 'package:flutter/widgets.dart';

import '../../domain/remote_control_config.dart';

class RemoteControlPagePortConfigHelper {
  const RemoteControlPagePortConfigHelper();

  String normalizeHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final slashIndex = trimmed.indexOf('/');
    if (slashIndex <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, slashIndex);
  }

  List<RemoteControlPortConfig> buildCandidatePorts(
    RemoteControlPortConfig? portConfig,
  ) {
    if (portConfig != null) {
      return <RemoteControlPortConfig>[portConfig];
    }

    return <RemoteControlPortConfig>[
      for (final basePort in RemoteControlPortConfig.shuffledBasePorts())
        RemoteControlPortConfig.fromBasePort(basePort),
    ];
  }

  RemoteControlPortConfig resolvePorts(RemoteControlPortConfig? ports) {
    return ports ??
        const RemoteControlPortConfig(controlPort: 18080, screenPort: 18081);
  }

  void applyPortConfigToInputs({
    required TextEditingController controlPortController,
    required TextEditingController screenPortController,
    required RemoteControlPortConfig? ports,
  }) {
    final resolved = resolvePorts(ports);
    controlPortController.text = '${resolved.controlPort}';
    screenPortController.text = '${resolved.screenPort}';
  }

  RemoteControlPortConfig updateControlPort(
    RemoteControlPortConfig? current,
    int value,
  ) {
    return RemoteControlPortConfig(
      controlPort: value,
      screenPort: current?.screenPort ?? 18081,
    );
  }

  RemoteControlPortConfig updateScreenPort(
    RemoteControlPortConfig? current,
    int value,
  ) {
    return RemoteControlPortConfig(
      controlPort: current?.controlPort ?? 18080,
      screenPort: value,
    );
  }
}
