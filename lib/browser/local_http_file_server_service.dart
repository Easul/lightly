import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/logging/runtime_logger.dart';
import '../core/network/local_network_address_resolver.dart';
import '../features/local_sharing/local_http/local_http_server_config.dart';
import 'local_http_directory_handler.dart';
import 'local_http_file_handler.dart';
import 'local_http_upload_handler.dart';

class LocalHttpFileServerService {
  LocalHttpFileServerService._();

  static final LocalHttpFileServerService _instance =
      LocalHttpFileServerService._();

  factory LocalHttpFileServerService({RuntimeLogger? runtimeLogger}) {
    if (runtimeLogger != null) {
      _instance._runtimeLogger = runtimeLogger;
    }
    return _instance;
  }

  final StreamController<LocalHttpFileServerState> _stateController =
      StreamController<LocalHttpFileServerState>.broadcast();

  HttpServer? _server;
  Directory? _rootDirectory;
  String? _rootCanonicalPath;
  int? _configuredPort;
  String? _uploadKey;
  bool _bindAllInterfaces = false;
  List<String> _lanUrls = const <String>[];
  RuntimeLogger? _runtimeLogger;
  final LocalHttpFileHandler _fileHandler = const LocalHttpFileHandler();
  final LocalHttpDirectoryHandler _directoryHandler =
      const LocalHttpDirectoryHandler();
  final LocalHttpUploadHandler _uploadHandler = const LocalHttpUploadHandler();

  Stream<LocalHttpFileServerState> get stateStream => _stateController.stream;
  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  int? get configuredPort => _configuredPort;
  String? get rootPath => _rootDirectory?.path;
  String? get baseUrl => _server == null
      ? null
      : 'http://${_bindAllInterfaces ? '0.0.0.0' : 'localhost'}:${_server!.port}';
  List<String> get lanUrls => List<String>.unmodifiable(_lanUrls);

  String getServerAddress() {
    if (_server == null) return '';
    final address = _bindAllInterfaces ? '0.0.0.0' : '127.0.0.1';
    return 'http://$address:${_server!.port}';
  }

  void setUploadKey(String? key) {
    _uploadKey = key?.trim();
  }

  bool get hasUploadKey => _uploadKey != null && _uploadKey!.isNotEmpty;

  bool validateUploadKey(String? key) {
    if (_uploadKey == null || _uploadKey!.isEmpty) return true;
    return key == _uploadKey;
  }

  void _logUploadEvent(String message, {Object? error}) {
    if (error != null) {
      _recordRuntimeLog(message, error: error);
      return;
    }
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  Future<void> applySettings(LocalHttpServerConfig config) async {
    if (!config.enabled) {
      await stop();
      return;
    }
    final validationError = config.validationError;
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    await startWithKey(
      rootPath: config.rootPath.trim(),
      preferredPort: config.port,
      bindAllInterfaces: config.bindAllInterfaces,
      uploadKey: config.uploadKey,
    );
  }

  Future<void> start({
    required String rootPath,
    int? preferredPort,
    bool bindAllInterfaces = false,
  }) async {
    final trimmedRoot = rootPath.trim();
    if (trimmedRoot.isEmpty) {
      throw ArgumentError('Root path is required');
    }

    final directory = Directory(trimmedRoot);
    if (!await directory.exists()) {
      throw FileSystemException('Root directory does not exist', trimmedRoot);
    }

    final canonicalRoot = await directory.resolveSymbolicLinks();
    await stop();

    _emit(LocalHttpFileServerState.starting);
    _bindAllInterfaces = bindAllInterfaces;
    _configuredPort = preferredPort;
    _rootDirectory = directory;
    _rootCanonicalPath = canonicalRoot;

    final address = bindAllInterfaces
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    _server = await HttpServer.bind(address, preferredPort ?? 0, shared: true);
    _lanUrls = bindAllInterfaces
        ? await resolvePrivateNetworkUrls(port: _server!.port)
        : const <String>[];
    _server!.listen(
      (request) {
        unawaited(_handleRequest(request));
      },
      onError: (_) {
        _emit(LocalHttpFileServerState.stopped);
      },
      cancelOnError: false,
    );

    _emit(LocalHttpFileServerState.started);
  }

  Future<void> startWithKey({
    required String rootPath,
    int? preferredPort,
    bool bindAllInterfaces = false,
    String? uploadKey,
  }) async {
    _uploadKey = uploadKey;
    await start(
      rootPath: rootPath,
      preferredPort: preferredPort,
      bindAllInterfaces: bindAllInterfaces,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _rootDirectory = null;
    _rootCanonicalPath = null;
    _configuredPort = null;
    _lanUrls = const <String>[];
    if (server != null) {
      _emit(LocalHttpFileServerState.stopping);
      await server.close(force: true);
    }
    _emit(LocalHttpFileServerState.stopped);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'OPTIONS') {
        _addCorsHeaders(request.response);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      if (request.uri.path == '/_upload' && request.method == 'POST') {
        await _uploadHandler.handleUpload(
          request,
          uploadKey: _uploadKey,
          rootCanonicalPath: _rootCanonicalPath,
          resolvePath: _resolvePath,
          addCorsHeaders: _addCorsHeaders,
          logDebug: _logUploadEvent,
        );
        return;
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.headers.set(
          HttpHeaders.allowHeader,
          'GET, HEAD, POST, OPTIONS',
        );
        await request.response.close();
        return;
      }

      final targetPath = _resolvePath(request.uri.path);
      if (targetPath == null) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
      switch (type) {
        case FileSystemEntityType.file:
          await _fileHandler.serveFile(request, File(targetPath));
          return;
        case FileSystemEntityType.directory:
          await _directoryHandler.serveDirectory(
            request,
            Directory(targetPath),
            hasUploadKey: hasUploadKey,
            serveFile: _fileHandler.serveFile,
          );
          return;
        case FileSystemEntityType.notFound:
        case FileSystemEntityType.link:
        case FileSystemEntityType.unixDomainSock:
        case FileSystemEntityType.pipe:
          if (await _fileHandler.tryServeSpaFallback(
            request,
            rootCanonicalPath: _rootCanonicalPath,
            serveFile: _fileHandler.serveFile,
          )) {
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
      }
    } on FileSystemException catch (e) {
      _recordRuntimeLog(
        'File system request failed',
        error: e,
        metadata: <String, Object?>{
          'method': request.method,
          'path': request.uri.path,
        },
      );
      await _writeErrorResponse(
        request.response,
        _statusCodeForFileSystemError(e),
        'File system error: ${e.message}',
      );
    } catch (e, stackTrace) {
      _recordRuntimeLog(
        'Request handling failed',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'method': request.method,
          'path': request.uri.path,
        },
      );
      await _writeErrorResponse(
        request.response,
        HttpStatus.internalServerError,
        'Internal Server Error: $e',
      );
    }
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS, HEAD',
    );
    response.headers.add('Access-Control-Allow-Headers', '*');
  }

  String? _resolvePath(String requestPath) {
    final canonicalRoot = _rootCanonicalPath;
    if (canonicalRoot == null) {
      return null;
    }

    final decoded = Uri.decodeComponent(requestPath);
    final trimmed = decoded.startsWith('/') ? decoded.substring(1) : decoded;
    final normalizedRelative = p.normalize(trimmed);
    if (p.isAbsolute(normalizedRelative) ||
        normalizedRelative.startsWith('..')) {
      return null;
    }

    final combined = p.normalize(p.join(canonicalRoot, normalizedRelative));
    if (combined != canonicalRoot && !p.isWithin(canonicalRoot, combined)) {
      return null;
    }
    return combined;
  }

  Future<void> _writeErrorResponse(
    HttpResponse response,
    int statusCode,
    String body,
  ) async {
    try {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.text;
      response.write(body);
    } catch (_) {}
    await response.close();
  }

  int _statusCodeForFileSystemError(FileSystemException error) {
    final osError = error.osError;
    final message = '${error.message} ${osError?.message ?? ''}'.toLowerCase();
    if (osError?.errorCode == 13 || message.contains('permission denied')) {
      return HttpStatus.forbidden;
    }
    return HttpStatus.notFound;
  }

  void _recordRuntimeLog(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    developer.log(
      message,
      name: 'LocalHttpFileServer',
      error: error,
      stackTrace: stackTrace,
    );
    final runtimeLogger = _runtimeLogger;
    if (runtimeLogger == null) {
      return;
    }
    unawaited(
      runtimeLogger
          .log(
            '[LocalHttpFileServer] $message',
            error: error,
            stackTrace: stackTrace,
            metadata: metadata,
          )
          .catchError((_) {}),
    );
  }

  void _emit(LocalHttpFileServerState state) {
    _stateController.add(state);
  }
}

enum LocalHttpFileServerState { starting, started, stopping, stopped }
