import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/utils/local_network_address_helper.dart';

class SimpleFileManagerSettings {
  const SimpleFileManagerSettings({
    required this.enabled,
    required this.rootPath,
    required this.port,
    required this.bindAllInterfaces,
    required this.favoritePaths,
  });

  static const int defaultPort = 12580;
  static const String defaultRootPath = '/storage/emulated/0';

  final bool enabled;
  final String rootPath;
  final int port;
  final bool bindAllInterfaces;
  final List<String> favoritePaths;

  factory SimpleFileManagerSettings.defaults() {
    return const SimpleFileManagerSettings(
      enabled: false,
      rootPath: defaultRootPath,
      port: defaultPort,
      bindAllInterfaces: true,
      favoritePaths: <String>[],
    );
  }

  SimpleFileManagerSettings copyWith({
    bool? enabled,
    String? rootPath,
    int? port,
    bool? bindAllInterfaces,
    List<String>? favoritePaths,
  }) {
    return SimpleFileManagerSettings(
      enabled: enabled ?? this.enabled,
      rootPath: rootPath ?? this.rootPath,
      port: port ?? this.port,
      bindAllInterfaces: bindAllInterfaces ?? this.bindAllInterfaces,
      favoritePaths: favoritePaths ?? this.favoritePaths,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'rootPath': rootPath,
      'port': port,
      'bindAllInterfaces': bindAllInterfaces,
      'favoritePaths': favoritePaths,
    };
  }

  factory SimpleFileManagerSettings.fromJson(Map<String, dynamic> json) {
    return SimpleFileManagerSettings(
      enabled: json['enabled'] as bool? ?? false,
      rootPath:
          json['rootPath'] as String? ??
          SimpleFileManagerSettings.defaultRootPath,
      port:
          (json['port'] as num?)?.toInt() ??
          SimpleFileManagerSettings.defaultPort,
      bindAllInterfaces: json['bindAllInterfaces'] as bool? ?? true,
      favoritePaths:
          (json['favoritePaths'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .where((path) => path.trim().isNotEmpty)
              .toList(growable: false),
    );
  }

  String? get validationError {
    if (rootPath.trim().isEmpty) {
      return '文件根目录不能为空';
    }
    if (port <= 0 || port > 65535) {
      return '文件简易管理端口必须是 1-65535';
    }
    return null;
  }
}

class SimpleFileManagerService {
  SimpleFileManagerService._();

  static final SimpleFileManagerService _instance =
      SimpleFileManagerService._();
  static const String _storageKey = 'simple_file_manager_settings';
  static const int _maxEditableBytes = 5 * 1024 * 1024;

  factory SimpleFileManagerService() => _instance;

  final StreamController<SimpleFileManagerState> _stateController =
      StreamController<SimpleFileManagerState>.broadcast();

  HttpServer? _server;
  Directory? _rootDirectory;
  String? _rootCanonicalPath;
  SimpleFileManagerSettings _settings = SimpleFileManagerSettings.defaults();
  List<String> _lanUrls = const <String>[];

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

  Future<void> applySettings(SimpleFileManagerSettings settings) async {
    await saveSettings(settings);
    if (!settings.enabled) {
      await stop();
      return;
    }
    await start(settings: _settings);
  }

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
      (request) => unawaited(_handleRequest(request)),
      onError: (_) => _emit(SimpleFileManagerState.stopped),
      cancelOnError: false,
    );
    _emit(SimpleFileManagerState.started);
  }

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

  Future<void> _handleRequest(HttpRequest request) async {
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
        await _writeJson(request.response, <String, Object?>{
          'rootPath': _settings.rootPath,
          'favorites': _settings.favoritePaths,
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
      if (kDebugMode) {
        debugPrint('Simple file manager error: $error');
        debugPrint('$stackTrace');
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
        'favorite': _settings.favoritePaths.contains(entity.path),
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
      'rootPath': _settings.rootPath,
      'path': targetPath,
      'parentPath': _parentInsideRoot(targetPath),
      'entries': entries,
      'favorites': _settings.favoritePaths,
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
      'favorite': _settings.favoritePaths.contains(targetPath),
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
    final favorites = _settings.favoritePaths
        .where((path) => path != targetPath)
        .toList(growable: false);
    if (favorites.length != _settings.favoritePaths.length) {
      await saveSettings(_settings.copyWith(favoritePaths: favorites));
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
    final favorites = <String>{..._settings.favoritePaths, targetPath}.toList()
      ..sort();
    await saveSettings(_settings.copyWith(favoritePaths: favorites));
    await _writeJson(request.response, <String, Object?>{
      'favorites': favorites,
    });
  }

  Future<void> _removeFavorite(HttpRequest request) async {
    final targetPath = await _resolveSafePath(
      request.uri.queryParameters['path'],
    );
    final favorites = _settings.favoritePaths
        .where((path) => path != targetPath)
        .toList(growable: false);
    await saveSettings(_settings.copyWith(favoritePaths: favorites));
    await _writeJson(request.response, <String, Object?>{
      'favorites': favorites,
    });
  }

  Future<String> _resolveSafePath(String? requestedPath) async {
    final canonicalRoot = _rootCanonicalPath;
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
    final canonicalRoot = _rootCanonicalPath;
    if (canonicalRoot == null || targetPath == canonicalRoot) return null;
    final parent = p.dirname(targetPath);
    if (parent == canonicalRoot || p.isWithin(canonicalRoot, parent)) {
      return parent;
    }
    return null;
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

  Future<void> _serveHtml(HttpResponse response) async {
    response.headers.contentType = ContentType.html;
    response.write(_htmlPage);
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

  void _emit(SimpleFileManagerState state) {
    _stateController.add(state);
  }
}

enum SimpleFileManagerState { starting, started, stopping, stopped }

const String _htmlPage = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>文件简易管理</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100dvh; display: flex; flex-direction: column; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f4f6fb; color: #1f2937; }
  header { padding: 18px 22px; background: #fff; border-bottom: 1px solid #e5e7eb; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
  h1 { margin: 0; font-size: 20px; }
  .status { color: #667085; font-size: 13px; word-break: break-all; }
  main { flex: 1; min-height: 0; display: grid; grid-template-columns: 330px 1fr; gap: 14px; padding: 14px; }
  aside, section { min-height: 0; background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; overflow: hidden; box-shadow: 0 8px 22px rgba(15,23,42,.05); }
  aside { display: flex; flex-direction: column; }
  .pane-title { padding: 14px 16px; border-bottom: 1px solid #eef2f7; font-weight: 700; display: flex; justify-content: space-between; gap: 8px; align-items: center; }
  .toolbar { padding: 12px; display: flex; gap: 8px; border-bottom: 1px solid #eef2f7; }
  input { width: 100%; border: 1px solid #d0d5dd; border-radius: 10px; padding: 10px 12px; font-size: 14px; }
  button { border: 0; border-radius: 10px; padding: 9px 12px; background: #eef2ff; color: #3730a3; font-weight: 700; cursor: pointer; white-space: nowrap; }
  button.primary { background: #4f46e5; color: white; }
  button.danger { background: #fee2e2; color: #b42318; }
  button.icon { padding: 6px 8px; border-radius: 8px; font-size: 12px; }
  button.ghost { background: transparent; color: #667085; }
  button:disabled { opacity: .5; cursor: not-allowed; }
  .list { overflow: auto; padding: 8px; }
  .entry { width: 100%; display: flex; align-items: center; gap: 8px; padding: 10px; border-radius: 10px; cursor: pointer; }
  .entry:hover, .entry.active { background: #f2f4ff; }
  .entry-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .entry-meta { color: #98a2b3; font-size: 12px; }
  .favorite { color: #f59e0b; }
  .editor { display: grid; grid-template-rows: auto 1fr; height: 100%; }
  .editor-head { padding: 12px 16px; border-bottom: 1px solid #eef2f7; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
  .file-title { min-width: 0; }
  .file-title strong, .file-title span { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-title span { color: #667085; font-size: 12px; margin-top: 3px; }
  textarea { width: 100%; height: 100%; resize: none; border: 0; outline: none; padding: 16px; font: 14px/1.6 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  .empty { height: 100%; display: grid; place-items: center; color: #667085; text-align: center; padding: 24px; }
  .split { display: grid; grid-template-rows: minmax(0, 1fr) minmax(150px, 32%); min-height: 0; }
  .favorites { border-top: 1px solid #eef2f7; display: grid; grid-template-rows: auto minmax(0, 1fr); min-height: 0; overflow: hidden; }
  .favorites .list { min-height: 0; overflow: auto; padding-bottom: 22px; }
  .toast { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); background: #111827; color: #fff; padding: 10px 14px; border-radius: 999px; opacity: 0; transition: opacity .2s; pointer-events: none; max-width: 92vw; }
  .toast.show { opacity: 1; }
  @media (max-width: 760px) {
    header { align-items: flex-start; flex-direction: column; gap: 8px; padding: 12px; }
    h1 { font-size: 18px; }
    main { grid-template-columns: 1fr; grid-template-rows: minmax(260px, 40dvh) minmax(0, 1fr); gap: 10px; padding: 10px; }
    aside, section, .editor { min-height: 0; }
    .editor-head { align-items: stretch; flex-direction: column; }
    .split { grid-template-rows: minmax(0, 1fr) minmax(112px, 28%); }
    .pane-title { padding: 12px 14px; }
    .toolbar { padding: 10px; }
    .list { padding: 6px; }
    .entry { padding: 8px 10px; }
    textarea { padding: 14px; font-size: 13px; }
    .editor-head .actions { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
  }
</style>
</head>
<body>
<header>
  <div><h1>文件简易管理</h1><div class="status" id="pathLabel">加载中...</div></div>
  <button onclick="loadTree(currentPath)">刷新</button>
</header>
<main>
  <aside>
    <div class="pane-title"><span>文件树</span><button class="ghost" onclick="goRoot()">根目录</button></div>
    <div class="toolbar"><input id="pathInput" placeholder="输入路径后回车"><button onclick="loadTree(pathInput.value)">打开</button></div>
    <div class="split">
      <div class="list" id="tree"></div>
      <div class="favorites"><div class="pane-title">收藏路径</div><div class="list" id="favorites"></div></div>
    </div>
  </aside>
  <section id="editorPanel"><div class="empty">请选择左侧的文本文件进行编辑。</div></section>
</main>
<div class="toast" id="toast"></div>
<script>
let rootPath = '';
let currentPath = '';
let currentFile = '';
let favorites = [];
const tree = document.getElementById('tree');
const favoritesEl = document.getElementById('favorites');
const pathInput = document.getElementById('pathInput');
const pathLabel = document.getElementById('pathLabel');
const editorPanel = document.getElementById('editorPanel');
pathInput.addEventListener('keydown', e => { if (e.key === 'Enter') loadTree(pathInput.value); });
document.addEventListener('keydown', e => {
  if ((e.ctrlKey || e.metaKey) && e.key && e.key.toLowerCase() === 's') {
    e.preventDefault();
    if (currentFile) saveFile();
  }
});
function toast(message) { const el = document.getElementById('toast'); el.textContent = message; el.classList.add('show'); setTimeout(() => el.classList.remove('show'), 2200); }
async function api(url, options) { const res = await fetch(url, options); const data = await res.json().catch(() => ({})); if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status)); return data; }
async function loadTree(path) {
  try {
    const data = await api('/api/tree?path=' + encodeURIComponent(path || ''));
    rootPath = data.rootPath; currentPath = data.path; favorites = data.favorites || [];
    pathInput.value = currentPath; pathLabel.textContent = currentPath;
    renderTree(data); renderFavorites();
  } catch (e) { toast('打开目录失败：' + e.message); }
}
function renderTree(data) {
  tree.innerHTML = '';
  if (data.parentPath) tree.appendChild(entry({name:'..', path:data.parentPath, type:'directory'}, true));
  for (const item of data.entries) tree.appendChild(entry(item, false));
}
function entry(item) {
  const row = document.createElement('div'); row.className = 'entry' + (item.path === currentFile ? ' active' : '');
  const icon = item.type === 'directory' ? '📁' : (item.editable ? '📝' : '📄');
  row.innerHTML = '<span>' + icon + '</span><span class="entry-name"></span><span class="entry-meta">' + (item.favorite ? '★' : '') + '</span>' + (item.type === 'file' ? '<button class="danger icon" title="删除文件">删除</button>' : '');
  row.querySelector('.entry-name').textContent = item.name;
  row.title = item.path;
  const deleteBtn = row.querySelector('button');
  if (deleteBtn) deleteBtn.onclick = e => { e.stopPropagation(); confirmDeleteFile(item.path, item.name); };
  row.onclick = () => item.type === 'directory' ? loadTree(item.path) : (item.editable ? openFile(item.path) : toast('该文件类型暂不支持编辑'));
  return row;
}
function renderFavorites() {
  favoritesEl.innerHTML = '';
  if (!favorites.length) { favoritesEl.innerHTML = '<div class="entry"><span class="entry-name">暂无收藏</span></div>'; return; }
  for (const path of favorites) {
    const row = document.createElement('div'); row.className = 'entry'; row.title = path;
    row.innerHTML = '<span class="favorite">★</span><span class="entry-name"></span><button class="ghost">移除</button>';
    row.querySelector('.entry-name').textContent = path;
    row.querySelector('.entry-name').onclick = () => openPath(path);
    row.querySelector('button').onclick = e => { e.stopPropagation(); removeFavorite(path); };
    favoritesEl.appendChild(row);
  }
}
async function openPath(path) { try { await openFile(path); } catch (_) { loadTree(path); } }
async function openFile(path) {
  const data = await api('/api/file?path=' + encodeURIComponent(path)); currentFile = data.path;
  editorPanel.innerHTML = '<div class="editor"><div class="editor-head"><div class="file-title"><strong></strong><span></span></div><div class="actions"><button id="favBtn"></button><button class="danger" id="deleteBtn">删除</button><button class="primary" id="saveBtn">保存</button></div></div><textarea id="content"></textarea></div>';
  editorPanel.querySelector('strong').textContent = data.name; editorPanel.querySelector('span').textContent = data.path;
  document.getElementById('content').value = data.content;
  document.getElementById('saveBtn').onclick = saveFile;
  document.getElementById('deleteBtn').onclick = () => confirmDeleteFile(data.path, data.name);
  document.getElementById('favBtn').textContent = data.favorite ? '取消收藏' : '收藏路径';
  document.getElementById('favBtn').onclick = () => data.favorite ? removeFavorite(data.path) : addFavorite(data.path);
}
async function saveFile() {
  if (!currentFile) return;
  try { await api('/api/file', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({path: currentFile, content: document.getElementById('content').value})}); toast('已保存'); }
  catch (e) { toast('保存失败：' + e.message); }
}
async function addFavorite(path) { try { const data = await api('/api/favorites', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({path})}); favorites = data.favorites || []; renderFavorites(); toast('已收藏'); } catch (e) { toast('收藏失败：' + e.message); } }
async function removeFavorite(path) { try { const data = await api('/api/favorites?path=' + encodeURIComponent(path), {method:'DELETE'}); favorites = data.favorites || []; renderFavorites(); toast('已移除收藏'); } catch (e) { toast('移除失败：' + e.message); } }
async function confirmDeleteFile(path, name) {
  if (!confirm('确定删除文件 “' + name + '”？\n\n此操作不可撤销。')) return;
  try {
    const data = await api('/api/file?path=' + encodeURIComponent(path), {method:'DELETE'});
    favorites = data.favorites || favorites.filter(item => item !== path);
    if (currentFile === path) {
      currentFile = '';
      editorPanel.innerHTML = '<div class="empty">文件已删除，请从左侧选择其他文本文件。</div>';
    }
    renderFavorites();
    await loadTree(currentPath);
    toast('已删除文件');
  } catch (e) { toast('删除失败：' + e.message); }
}
function goRoot() { loadTree(rootPath); }
loadTree('');
</script>
</body>
</html>
''';
