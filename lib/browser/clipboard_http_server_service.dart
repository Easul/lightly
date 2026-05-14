import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'clipboard_storage_service.dart';
import 'utils/local_network_address_helper.dart';

class ClipboardHttpServerService {
  ClipboardHttpServerService._();

  static final ClipboardHttpServerService _instance =
      ClipboardHttpServerService._();
  factory ClipboardHttpServerService() => _instance;

  final ClipboardStorageService _storage = ClipboardStorageService();
  final StreamController<ClipboardHttpServerState> _stateController =
      StreamController<ClipboardHttpServerState>.broadcast();

  HttpServer? _server;
  int? _configuredPort;
  List<String> _lanUrls = const <String>[];

  Stream<ClipboardHttpServerState> get stateStream => _stateController.stream;
  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  int? get configuredPort => _configuredPort;

  String? get baseUrl =>
      _server == null ? null : 'http://0.0.0.0:${_server!.port}';

  String? get localUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';
  List<String> get lanUrls => List<String>.unmodifiable(_lanUrls);

  Future<void> start({int? preferredPort}) async {
    await stop();
    _emit(ClipboardHttpServerState.starting);

    final requestedPort = preferredPort ?? 0;
    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        requestedPort,
        shared: true,
      );

      _server = server;
      _configuredPort = preferredPort;
      _lanUrls = await resolvePrivateNetworkUrls(port: server.port);

      server.listen(
        (request) {
          unawaited(_handleRequest(request));
        },
        onDone: () {
          _server = null;
          _emit(ClipboardHttpServerState.stopped);
        },
        onError: (_) {
          _server = null;
          _emit(ClipboardHttpServerState.stopped);
        },
        cancelOnError: false,
      );

      _emit(ClipboardHttpServerState.started);
    } catch (_) {
      _server = null;
      _configuredPort = null;
      _emit(ClipboardHttpServerState.stopped);
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _configuredPort = null;
    _lanUrls = const <String>[];
    if (server != null) {
      _emit(ClipboardHttpServerState.stopping);
      await server.close(force: true);
    }
    _emit(ClipboardHttpServerState.stopped);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      _addCorsHeaders(request.response);

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/') {
        await _serveHtmlPage(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/save') {
        await _handleSave(request);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
    } catch (e, stackTrace) {
      debugPrint('Clipboard HTTP server error: $e');
      debugPrint('Stack trace: $stackTrace');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error');
      } catch (_) {
        // response may have already started
      }
      await request.response.close();
    }
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }

  Future<void> _serveHtmlPage(HttpRequest request) async {
    final content = await _storage.loadContent();
    final escapedContent = const HtmlEscape().convert(content);

    final body =
        '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>剪贴板</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f5f5f5;
    padding: 20px;
    max-width: 800px;
    margin: 0 auto;
  }
  h1 { color: #333; margin-bottom: 20px; font-size: 24px; }
  .info { color: #666; font-size: 14px; margin-bottom: 16px; }
  textarea {
    width: 100%;
    min-height: 300px;
    padding: 16px;
    border: 1px solid #ddd;
    border-radius: 12px;
    font-size: 16px;
    line-height: 1.6;
    resize: vertical;
    font-family: monospace;
  }
  textarea:focus { outline: none; border-color: #5B5BD6; }
  .actions {
    margin-top: 16px;
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
  }
  button {
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    cursor: pointer;
    transition: opacity 0.2s;
  }
  button:hover { opacity: 0.9; }
  .btn-primary { background: #5B5BD6; color: white; }
  .btn-secondary { background: #e0e0e0; color: #333; }
  #status {
    margin-top: 12px;
    padding: 10px 16px;
    border-radius: 8px;
    font-size: 14px;
    display: none;
  }
  #status.success { background: #e8f5e9; color: #2e7d32; display: block; }
  #status.error { background: #ffebee; color: #c62828; display: block; }
</style>
</head>
<body>
<h1>剪贴板</h1>
<p class="info">内容会自动保存到系统剪贴板。页面每 3 秒自动刷新以同步最新内容。</p>
<textarea id="content" placeholder="在此输入或粘贴内容...">$escapedContent</textarea>
<div class="actions">
  <button class="btn-primary" onclick="saveContent()">保存到剪贴板</button>
  <button class="btn-secondary" onclick="refreshContent()">刷新</button>
</div>
<div id="status"></div>
<script>
  let isEditing = false;
  const textarea = document.getElementById('content');
  textarea.addEventListener('focus', () => { isEditing = true; });
  textarea.addEventListener('blur', () => { isEditing = false; });

  function showStatus(msg, isError) {
    const el = document.getElementById('status');
    el.textContent = msg;
    el.className = isError ? 'error' : 'success';
    setTimeout(() => { el.className = ''; el.textContent = ''; }, 3000);
  }

  async function saveContent() {
    const text = textarea.value;
    try {
      const res = await fetch('/save', {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        body: text
      });
      if (res.ok) {
        showStatus('已保存到剪贴板', false);
      } else {
        showStatus('保存失败: ' + res.status, true);
      }
    } catch (e) {
      showStatus('保存失败: ' + e.message, true);
    }
  }

  async function refreshContent() {
    if (isEditing) return;
    try {
      const res = await fetch('/');
      const html = await res.text();
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');
      const newText = doc.getElementById('content').value;
      if (newText !== textarea.value) {
        textarea.value = newText;
      }
    } catch (e) {
      console.log('Refresh failed:', e);
    }
  }

  setInterval(refreshContent, 3000);
</script>
</body>
</html>
''';

    request.response.headers.contentType = ContentType.html;
    request.response.write(body);
    await request.response.close();
  }

  Future<void> _handleSave(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    await _storage.saveContent(body);

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'success': true}));
    await request.response.close();
  }

  void _emit(ClipboardHttpServerState state) {
    _stateController.add(state);
  }
}

enum ClipboardHttpServerState { starting, started, stopping, stopped }
