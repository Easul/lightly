import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/local_sharing/local_http/local_http_file_server_service.dart';
import '../../features/proxy/infrastructure/proxy_service.dart';

class BrowserProxyStatusMonitor {
  BrowserProxyStatusMonitor({
    required ProxyService proxyService,
    required LocalHttpFileServerService localHttpFileServerService,
  }) : _proxyService = proxyService,
       _localHttpFileServerService = localHttpFileServerService,
       proxyState = ValueNotifier<ProxyState>(proxyService.currentState),
       localHttpState = ValueNotifier<LocalHttpFileServerState>(
         localHttpFileServerService.isRunning
             ? LocalHttpFileServerState.started
             : LocalHttpFileServerState.stopped,
       );

  final ProxyService _proxyService;
  final LocalHttpFileServerService _localHttpFileServerService;
  final ValueNotifier<ProxyState> proxyState;
  final ValueNotifier<LocalHttpFileServerState> localHttpState;

  StreamSubscription<ProxyState>? _proxyStateSubscription;
  StreamSubscription<LocalHttpFileServerState>? _localHttpStateSubscription;

  void start() {
    _proxyStateSubscription ??= _proxyService.stateStream.listen((state) {
      proxyState.value = state;
    });
    _localHttpStateSubscription ??= _localHttpFileServerService.stateStream
        .listen((state) {
          localHttpState.value = state;
        });
  }

  void syncSnapshot() {
    proxyState.value = _proxyService.currentState;
    localHttpState.value = _localHttpFileServerService.isRunning
        ? LocalHttpFileServerState.started
        : LocalHttpFileServerState.stopped;
  }

  void setProxyState(ProxyState state) {
    proxyState.value = state;
  }

  void setLocalHttpState(LocalHttpFileServerState state) {
    localHttpState.value = state;
  }

  void dispose() {
    _proxyStateSubscription?.cancel();
    _localHttpStateSubscription?.cancel();
    proxyState.dispose();
    localHttpState.dispose();
  }
}
