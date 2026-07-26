import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/logging/runtime_logger.dart';
import 'simple_file_manager_settings.dart';
import 'simple_file_manager_web_ui.dart';

typedef SimpleFileManagerSettingsReader = SimpleFileManagerSettings Function();
typedef SimpleFileManagerSettingsWriter =
    Future<void> Function(SimpleFileManagerSettings settings);
typedef SimpleFileManagerRuntimeLoggerReader = RuntimeLogger? Function();

class SimpleFileManagerRequestHandler {
  const SimpleFileManagerRequestHandler({
    required String? Function() rootCanonicalPath,
    required SimpleFileManagerSettingsReader settings,
    required SimpleFileManagerSettingsWriter saveSettings,
    required SimpleFileManagerRuntimeLoggerReader runtimeLogger,
  }) : _rootCanonicalPath = rootCanonicalPath,
       _settings = settings,
       _saveSettings = saveSettings,
       _runtimeLogger = runtimeLogger;

  static const int _maxEditableBytes = 5 * 1024 * 1024;

  final String? Function() _rootCanonicalPath;
  final SimpleFileManagerSettingsReader _settings;
  final SimpleFileManagerSettingsWriter _saveSettings;
  final SimpleFileManagerRuntimeLoggerReader _runtimeLogger;

  Future<void> handle(HttpRequest request) async {
    try {
      _addCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      if (request.method == 'GET' && path == '/') {
        await _serveHtml(request.response);
        return;
      }
      if (request.method == 'GET' && path == '/api/tree') {
        await _serveTree(request);
        return;
      }
      if (request.method == 'GET' && path == '/api/file') {
        await _serveFile(request);
        return;
      }
      if (request.method == 'POST' && path == '/api/file') {
        await _saveFile(request);
        return;
      }
      if (request.method == 'DELETE' && path == '/api/file') {
        await _deleteFile(request);
        return;
      }
      if (request.method == 'GET' && path == '/api/favorites') {
        final settings = _settings();
        await _writeJson(request.response, <String, Object?>{
          'rootPath': settings.rootPath,
          'favorites': settings.favoritePaths,
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/favorites') {
        await _addFavorite(request);
        return;
      }
      if (request.method == 'DELETE' && path == '/api/favorites') {
        await _removeFavorite(request);
        return;
      }

      await _writeError(request.response, HttpStatus.notFound, 'Not Found');
    } on FileSystemException catch (error) {
      await _writeError(
        request.response,
        _statusCodeForFileSystemError(error),
        error.message,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Request handling failed',
        name: 'SimpleFileManager',
        error: error,
        stackTrace: stackTrace,
      );
      final runtimeLogger = _runtimeLogger();
      if (runtimeLogger != null) {
        unawaited(
          runtimeLogger
              .log(
                '[SimpleFileManager] Request handling failed',
                error: error,
                stackTrace: stackTrace,
                metadata: <String, Object?>{
                  'method': request.method,
                  'path': request.uri.path,
                },
              )
              .catchError((_) {}),
        );
      }
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        error.toString(),
      );
    }
  }

  Future<void> _serveTree(HttpRequest request) async {
    final targetPath = await _resolveSafePath(
      request.uri.queryParameters['path'],
    );
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        'Not a directory',
      );
      return;
    }

    final settings = _settings();
    final directory = Directory(targetPath);
    final entries = <Map<String, Object?>>[];
    await for (final entity in directory.list(followLinks: false)) {
      final entityType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.file &&
          entityType != FileSystemEntityType.directory) {
        continue;
      }
      final stat = await entity.stat();
      final isFile = entityType == FileSystemEntityType.file;
      entries.add(<String, Object?>{
        'name': p.basename(entity.path),
        'path': entity.path,
        'type': isFile ? 'file' : 'directory',
        'editable': isFile && _isEditablePath(entity.path),
        'size': isFile ? stat.size : null,
        'modified': stat.modified.toIso8601String(),
        'favorite': settings.favoritePaths.contains(entity.path),
      });
    }
    entries.sort((a, b) {
      final typeCompare = (a['type'] as String).compareTo(b['type'] as String);
      if (typeCompare != 0) return typeCompare;
      return (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
    });

    await _writeJson(request.response, <String, Object?>{
      'rootPath': settings.rootPath,
      'path': targetPath,
      'parentPath': _parentInsideRoot(targetPath),
      'entries': entries,
      'favorites': settings.favoritePaths,
    });
  }

  Future<void> _serveFile(HttpRequest request) async {
    final targetPath = await _resolveSafePath(
      request.uri.queryParameters['path'],
    );
    await _ensureEditableFile(targetPath);
    final file = File(targetPath);
    final text = await file.readAsString();
    final stat = await file.stat();
    await _writeJson(request.response, <String, Object?>{
      'path': targetPath,
      'name': p.basename(targetPath),
      'content': text,
      'size': stat.size,
      'modified': stat.modified.toIso8601String(),
      'favorite': _settings().favoritePaths.contains(targetPath),
    });
  }

  Future<void> _saveFile(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final targetPath = await _resolveSafePath(payload['path'] as String?);
    await _ensureEditableFile(targetPath);
    final content = payload['content'] as String? ?? '';
    await File(targetPath).writeAsString(content, flush: true);
    await _writeJson(request.response, <String, Object?>{
      'ok': true,
      'path': targetPath,
      'modified': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _deleteFile(HttpRequest request) async {
    final targetPath = await _resolveSafePath(
      request.uri.queryParameters['path'],
    );
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Not a file', targetPath);
    }
    await File(targetPath).delete();
    final settings = _settings();
    final favorites = settings.favoritePaths
        .where((path) => path != targetPath)
        .toList(growable: false);
    if (favorites.length != settings.favoritePaths.length) {
      await _saveSettings(settings.copyWith(favoritePaths: favorites));
    }
    await _writeJson(request.response, <String, Object?>{
      'ok': true,
      'path': targetPath,
      'favorites': favorites,
    });
  }

  Future<void> _addFavorite(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final targetPath = await _resolveSafePath(payload['path'] as String?);
    final settings = _settings();
    final favorites = <String>{...settings.favoritePaths, targetPath}.toList()
      ..sort();
    await _saveSettings(settings.copyWith(favoritePaths: favorites));
    await _writeJson(request.response, <String, Object?>{
      'favorites': favorites,
    });
  }

  Future<void> _removeFavorite(HttpRequest request) async {
    final targetPath = await _resolveSafePath(
      request.uri.queryParameters['path'],
    );
    final settings = _settings();
    final favorites = settings.favoritePaths
        .where((path) => path != targetPath)
        .toList(growable: false);
    await _saveSettings(settings.copyWith(favoritePaths: favorites));
    await _writeJson(request.response, <String, Object?>{
      'favorites': favorites,
    });
  }

  Future<String> _resolveSafePath(String? requestedPath) async {
    final canonicalRoot = _rootCanonicalPath();
    if (canonicalRoot == null) {
      throw const FileSystemException('Service root is unavailable');
    }
    final raw = requestedPath?.trim();
    final candidate = raw == null || raw.isEmpty
        ? canonicalRoot
        : (p.isAbsolute(raw) ? raw : p.join(canonicalRoot, raw));
    final normalized = p.normalize(candidate);
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', normalized);
    }
    final canonical = type == FileSystemEntityType.directory
        ? await Directory(normalized).resolveSymbolicLinks()
        : await File(normalized).resolveSymbolicLinks();
    if (canonical != canonicalRoot && !p.isWithin(canonicalRoot, canonical)) {
      throw FileSystemException('Path is outside the managed root', normalized);
    }
    return canonical;
  }

  Future<void> _ensureEditableFile(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Not a file', targetPath);
    }
    if (!_isEditablePath(targetPath)) {
      throw FileSystemException('Unsupported text file type', targetPath);
    }
    final size = await File(targetPath).length();
    if (size > _maxEditableBytes) {
      throw FileSystemException('File is larger than 5MB', targetPath);
    }
  }

  bool _isEditablePath(String filePath) {
    const extensions = <String>{
      '.md',
      '.markdown',
      '.txt',
      '.text',
      '.html',
      '.htm',
      '.log',
      '.toml',
      '.yaml',
      '.yml',
      '.json',
      '.xml',
      '.css',
      '.js',
      '.ts',
      '.dart',
      '.kt',
      '.java',
      '.rs',
      '.py',
      '.sh',
      '.ini',
      '.conf',
      '.cfg',
      '.csv',
      '.sql',
      '.gradle',
      '.properties',
      '.gitignore',
      '.env',
    };
    final basename = p.basename(filePath).toLowerCase();
    return extensions.contains(p.extension(basename)) ||
        extensions.contains(basename);
  }

  String? _parentInsideRoot(String targetPath) {
    final canonicalRoot = _rootCanonicalPath();
    if (canonicalRoot == null || targetPath == canonicalRoot) return null;
    final parent = p.dirname(targetPath);
    if (parent == canonicalRoot || p.isWithin(canonicalRoot, parent)) {
      return parent;
    }
    return null;
  }

  Future<void> _serveHtml(HttpResponse response) async {
    response.headers.contentType = ContentType.html;
    response.write(simpleFileManagerHtmlPage);
    await response.close();
  }

  Future<void> _writeJson(HttpResponse response, Object data) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> _writeError(
    HttpResponse response,
    int statusCode,
    String message,
  ) async {
    try {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(<String, Object?>{'error': message}));
    } catch (_) {}
    await response.close();
  }

  int _statusCodeForFileSystemError(FileSystemException error) {
    final message = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    if (message.contains('outside')) return HttpStatus.forbidden;
    if (error.osError?.errorCode == 13 ||
        message.contains('permission denied')) {
      return HttpStatus.forbidden;
    }
    if (message.contains('unsupported') || message.contains('larger')) {
      return HttpStatus.badRequest;
    }
    return HttpStatus.notFound;
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, DELETE, OPTIONS',
    );
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }
}
