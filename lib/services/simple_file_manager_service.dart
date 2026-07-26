import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/runtime_logger.dart';
import '../core/network/local_network_address_resolver.dart';
import 'simple_file_manager_request_handler.dart';
import 'simple_file_manager_runtime.dart';
import 'simple_file_manager_settings.dart';

export 'simple_file_manager_settings.dart';

class SimpleFileManagerService implements SimpleFileManagerRuntime {
  SimpleFileManagerService._();

  static final SimpleFileManagerService _instance =
      SimpleFileManagerService._();
  static const String _storageKey = 'simple_file_manager_settings';

  factory SimpleFileManagerService({RuntimeLogger? runtimeLogger}) {
    if (runtimeLogger != null) {
      _instance._runtimeLogger = runtimeLogger;
    }
    return _instance;
  }

  final StreamController<SimpleFileManagerState> _stateController =
      StreamController<SimpleFileManagerState>.broadcast();
  late final SimpleFileManagerRequestHandler _requestHandler =
      SimpleFileManagerRequestHandler(
        rootCanonicalPath: () => _rootCanonicalPath,
        settings: () => _settings,
        saveSettings: saveSettings,
        runtimeLogger: () => _runtimeLogger,
      );

  HttpServer? _server;
  Directory? _rootDirectory;
  String? _rootCanonicalPath;
  SimpleFileManagerSettings _settings = SimpleFileManagerSettings.defaults();
  List<String> _lanUrls = const <String>[];
  RuntimeLogger? _runtimeLogger;

  Stream<SimpleFileManagerState> get stateStream => _stateController.stream;
  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  String? get rootPath => _rootDirectory?.path;
  SimpleFileManagerSettings get settings => _settings;
  List<String> get lanUrls => List<String>.unmodifiable(_lanUrls);

  String? get localUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';
  String? get baseUrl {
    final server = _server;
    if (server == null) return null;
    final host = _settings.bindAllInterfaces ? '0.0.0.0' : '127.0.0.1';
    return 'http://$host:${server.port}';
  }

  @override
  Future<SimpleFileManagerSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _settings = SimpleFileManagerSettings.defaults();
      return _settings;
    }
    _settings = SimpleFileManagerSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return _settings;
  }

  Future<void> saveSettings(SimpleFileManagerSettings settings) async {
    final validationError = settings.validationError;
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    final normalized = settings.copyWith(
      rootPath: settings.rootPath.trim(),
      favoritePaths: _normalizeFavorites(
        settings.rootPath,
        settings.favoritePaths,
      ),
    );
    _settings = normalized;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(normalized.toJson()));
  }

  @override
  Future<void> applySettings(SimpleFileManagerSettings settings) async {
    await saveSettings(settings);
    if (!settings.enabled) {
      await stop();
      return;
    }
    await start(settings: _settings);
  }

  @override
  Future<void> start({SimpleFileManagerSettings? settings}) async {
    final nextSettings = settings ?? _settings;
    final validationError = nextSettings.validationError;
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final directory = Directory(nextSettings.rootPath.trim());
    if (!await directory.exists()) {
      throw FileSystemException(
        'Root directory does not exist',
        directory.path,
      );
    }
    final canonicalRoot = await directory.resolveSymbolicLinks();

    await stop();
    _emit(SimpleFileManagerState.starting);
    _settings = nextSettings;
    _rootDirectory = directory;
    _rootCanonicalPath = canonicalRoot;

    final address = nextSettings.bindAllInterfaces
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    final server = await HttpServer.bind(
      address,
      nextSettings.port,
      shared: true,
    );
    _server = server;
    _lanUrls = nextSettings.bindAllInterfaces
        ? await resolvePrivateNetworkUrls(port: server.port)
        : const <String>[];
    server.listen(
      (request) => unawaited(_requestHandler.handle(request)),
      onError: (_) => _emit(SimpleFileManagerState.stopped),
      cancelOnError: false,
    );
    _emit(SimpleFileManagerState.started);
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _rootDirectory = null;
    _rootCanonicalPath = null;
    _lanUrls = const <String>[];
    if (server != null) {
      _emit(SimpleFileManagerState.stopping);
      await server.close(force: true);
    }
    _emit(SimpleFileManagerState.stopped);
  }

  List<String> _normalizeFavorites(String rootPath, List<String> paths) {
    final root = p.normalize(rootPath.trim());
    final normalized = <String>{};
    for (final rawPath in paths) {
      final path = p.normalize(rawPath.trim());
      if (path.isEmpty) continue;
      if (path == root || p.isWithin(root, path)) {
        normalized.add(path);
      }
    }
    return normalized.toList()..sort();
  }

  void _emit(SimpleFileManagerState state) {
    _stateController.add(state);
  }
}

enum SimpleFileManagerState { starting, started, stopping, stopped }
