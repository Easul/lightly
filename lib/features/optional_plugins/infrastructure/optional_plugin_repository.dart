import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/optional_feature.dart';
import '../domain/optional_plugin_download_settings.dart';
import '../domain/optional_plugin_manifest.dart';
import 'optional_plugin_manifest_loader.dart';

typedef OptionalPluginProxyResolver = String Function(Uri uri);
typedef OptionalPluginDownloadProgress = void Function(int received, int total);

class OptionalPluginRepositoryException implements Exception {
  const OptionalPluginRepositoryException(
    this.message, {
    this.retryable = false,
  });

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

class OptionalPluginDownloadAttempt {
  const OptionalPluginDownloadAttempt({
    required this.uri,
    required this.useProxy,
    required this.label,
    this.mirrorHost,
  });

  final Uri uri;
  final bool useProxy;
  final String label;
  final String? mirrorHost;
}

class OptionalPluginDownloadPlanner {
  const OptionalPluginDownloadPlanner();

  List<OptionalPluginDownloadAttempt> plan({
    required Uri source,
    required OptionalPluginDownloadSettings settings,
    required bool proxyAvailable,
  }) {
    final mirrorUri = settings.mirrorUri(source);
    final mirrorAttempt = OptionalPluginDownloadAttempt(
      uri: mirrorUri,
      useProxy: false,
      label: '镜像',
      mirrorHost: mirrorUri.host,
    );
    final githubAttempt = OptionalPluginDownloadAttempt(
      uri: source,
      useProxy: proxyAvailable,
      label: proxyAvailable ? 'GitHub（代理）' : 'GitHub（直连）',
    );
    return switch (settings.mode) {
      OptionalPluginDownloadMode.automatic => <OptionalPluginDownloadAttempt>[
        githubAttempt,
        mirrorAttempt,
      ],
      OptionalPluginDownloadMode.githubOnly => <OptionalPluginDownloadAttempt>[
        githubAttempt,
      ],
      OptionalPluginDownloadMode.mirrorOnly => <OptionalPluginDownloadAttempt>[
        mirrorAttempt,
      ],
    };
  }
}

class OptionalPluginConnectionTestResult {
  const OptionalPluginConnectionTestResult({
    required this.routeLabel,
    required this.elapsed,
  });

  final String routeLabel;
  final Duration elapsed;
}

class OptionalPluginRepository {
  OptionalPluginRepository({
    required OptionalPluginProxyResolver proxyResolver,
    required OptionalPluginDownloadSettings downloadSettings,
    required bool proxyAvailable,
    OptionalPluginManifestLoader? manifestLoader,
    OptionalPluginDownloadPlanner planner =
        const OptionalPluginDownloadPlanner(),
    Future<Directory> Function()? temporaryDirectory,
    HttpClient Function()? httpClientFactory,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration idleTimeout = const Duration(seconds: 10),
    Duration slowCheckWindow = const Duration(seconds: 8),
    int minimumBytesPerSecond = 48 * 1024,
    bool allowInsecureLocalhostForTesting = false,
  }) : _proxyResolver = proxyResolver,
       _downloadSettings = downloadSettings,
       _proxyAvailable = proxyAvailable,
       _manifestLoader = manifestLoader ?? OptionalPluginManifestLoader(),
       _planner = planner,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _connectTimeout = connectTimeout,
       _idleTimeout = idleTimeout,
       _slowCheckWindow = slowCheckWindow,
       _minimumBytesPerSecond = minimumBytesPerSecond,
       _allowInsecureLocalhostForTesting = allowInsecureLocalhostForTesting;

  final OptionalPluginProxyResolver _proxyResolver;
  final OptionalPluginDownloadSettings _downloadSettings;
  final bool _proxyAvailable;
  final OptionalPluginManifestLoader _manifestLoader;
  final OptionalPluginDownloadPlanner _planner;
  final Future<Directory> Function() _temporaryDirectory;
  final HttpClient Function() _httpClientFactory;
  final Duration _connectTimeout;
  final Duration _idleTimeout;
  final Duration _slowCheckWindow;
  final int _minimumBytesPerSecond;
  final bool _allowInsecureLocalhostForTesting;

  static const int _maximumRedirects = 5;
  static const Set<String> _trustedHostSuffixes = <String>{
    'github.com',
    'githubusercontent.com',
  };

  Future<OptionalPluginManifest> loadManifest() => _manifestLoader.load();

  Future<File> downloadArtifact(
    OptionalFeatureDescriptor descriptor,
    OptionalPluginRelease release,
    OptionalPluginArtifact artifact, {
    OptionalPluginDownloadProgress? onProgress,
  }) async {
    final root = Directory(
      path.join((await _temporaryDirectory()).path, 'optional_plugins'),
    );
    await root.create(recursive: true);
    final file = File(
      path.join(
        root.path,
        '${descriptor.id.wireName}-${release.versionCode}.apk',
      ),
    );
    final attempts = _planner.plan(
      source: artifact.url,
      settings: _downloadSettings,
      proxyAvailable: _proxyAvailable,
    );
    OptionalPluginRepositoryException? lastError;
    for (var index = 0; index < attempts.length; index++) {
      if (await file.exists()) {
        await file.delete();
      }
      onProgress?.call(0, artifact.size);
      try {
        await _downloadAttempt(
          attempt: attempts[index],
          file: file,
          expectedSize: artifact.size,
          onProgress: onProgress,
        );
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != artifact.sha256) {
          throw const OptionalPluginRepositoryException('插件包校验失败');
        }
        return file;
      } on OptionalPluginRepositoryException catch (error) {
        lastError = error;
        if (await file.exists()) {
          await file.delete();
        }
        final hasFallback = index + 1 < attempts.length;
        if (!error.retryable || !hasFallback) {
          rethrow;
        }
      } on Object catch (error) {
        if (await file.exists()) {
          await file.delete();
        }
        lastError = OptionalPluginRepositoryException(
          '${attempts[index].label}下载失败：$error',
          retryable: true,
        );
        if (index + 1 >= attempts.length) {
          throw lastError;
        }
      }
    }
    throw lastError ?? const OptionalPluginRepositoryException('插件下载失败');
  }

  Future<OptionalPluginConnectionTestResult> testArtifact(
    OptionalPluginArtifact artifact,
  ) async {
    final attempts = _planner.plan(
      source: artifact.url,
      settings: _downloadSettings,
      proxyAvailable: _proxyAvailable,
    );
    OptionalPluginRepositoryException? lastError;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final stopwatch = Stopwatch()..start();
      final client = _createClient(attempt);
      try {
        final response = await _open(client, attempt);
        await response.first.timeout(_idleTimeout);
        return OptionalPluginConnectionTestResult(
          routeLabel: attempt.label,
          elapsed: stopwatch.elapsed,
        );
      } catch (error) {
        lastError = OptionalPluginRepositoryException(
          '${attempt.label}连接失败：$error',
          retryable: true,
        );
        if (index + 1 >= attempts.length) {
          throw lastError;
        }
      } finally {
        client.close(force: true);
      }
    }
    throw lastError ?? const OptionalPluginRepositoryException('插件下载线路不可用');
  }

  Future<void> _downloadAttempt({
    required OptionalPluginDownloadAttempt attempt,
    required File file,
    required int expectedSize,
    OptionalPluginDownloadProgress? onProgress,
  }) async {
    final client = _createClient(attempt);
    try {
      final response = await _open(client, attempt);
      if (response.contentLength > 0 &&
          response.contentLength != expectedSize) {
        throw const OptionalPluginRepositoryException(
          '插件包大小与发布清单不一致',
          retryable: true,
        );
      }
      final sink = file.openWrite(mode: FileMode.writeOnly);
      final stopwatch = Stopwatch()..start();
      var received = 0;
      try {
        await for (final chunk in response.timeout(_idleTimeout)) {
          received += chunk.length;
          if (received > expectedSize) {
            throw const OptionalPluginRepositoryException('插件包超过发布清单声明的大小');
          }
          sink.add(chunk);
          onProgress?.call(received, expectedSize);
          if (_isPersistentlySlow(received, stopwatch.elapsed, expectedSize)) {
            throw OptionalPluginRepositoryException(
              '${attempt.label}下载速度持续过低，正在切换线路',
              retryable: true,
            );
          }
        }
      } on TimeoutException {
        throw OptionalPluginRepositoryException(
          '${attempt.label}长时间没有收到数据',
          retryable: true,
        );
      } finally {
        await sink.close();
      }
      if (received != expectedSize) {
        throw OptionalPluginRepositoryException(
          '插件包下载不完整：$received / $expectedSize',
          retryable: true,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  bool _isPersistentlySlow(int received, Duration elapsed, int expectedSize) {
    if (received >= expectedSize || elapsed < _slowCheckWindow) {
      return false;
    }
    final seconds = elapsed.inMilliseconds / 1000;
    return seconds > 0 && received / seconds < _minimumBytesPerSecond;
  }

  @visibleForTesting
  bool isPersistentlySlowForTesting({
    required int received,
    required Duration elapsed,
    required int expectedSize,
  }) {
    return _isPersistentlySlow(received, elapsed, expectedSize);
  }

  HttpClient _createClient(OptionalPluginDownloadAttempt attempt) {
    final client = _httpClientFactory();
    client.connectionTimeout = _connectTimeout;
    client.findProxy = attempt.useProxy ? _proxyResolver : (_) => 'DIRECT';
    return client;
  }

  Future<HttpClientResponse> _open(
    HttpClient client,
    OptionalPluginDownloadAttempt attempt,
  ) async {
    var current = attempt.uri;
    for (var redirect = 0; redirect <= _maximumRedirects; redirect++) {
      _validateUri(current, mirrorHost: attempt.mirrorHost);
      final request = await client.getUrl(current).timeout(_connectTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Lightly-Plugin-Installer',
      );
      final response = await request.close().timeout(_connectTimeout);
      if (!response.isRedirect) {
        if (response.statusCode != HttpStatus.ok) {
          await _drainResponse(response, attempt);
          throw OptionalPluginRepositoryException(
            '${attempt.label}返回 HTTP ${response.statusCode}',
            retryable: true,
          );
        }
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await _drainResponse(response, attempt);
      if (location == null ||
          location.isEmpty ||
          redirect == _maximumRedirects) {
        throw const OptionalPluginRepositoryException(
          '插件下载重定向无效',
          retryable: true,
        );
      }
      current = current.resolve(location);
    }
    throw const OptionalPluginRepositoryException(
      '插件下载重定向次数过多',
      retryable: true,
    );
  }

  Future<void> _drainResponse(
    HttpClientResponse response,
    OptionalPluginDownloadAttempt attempt,
  ) async {
    try {
      await response.drain<void>().timeout(_idleTimeout);
    } on TimeoutException {
      throw OptionalPluginRepositoryException(
        '${attempt.label}响应长时间没有结束',
        retryable: true,
      );
    }
  }

  void _validateUri(Uri uri, {String? mirrorHost}) {
    final host = uri.host.toLowerCase();
    if (_allowInsecureLocalhostForTesting &&
        uri.scheme == 'http' &&
        (host == 'localhost' || host == '127.0.0.1' || host == '::1')) {
      return;
    }
    final trustedGitHub = _trustedHostSuffixes.any(
      (suffix) => host == suffix || host.endsWith('.$suffix'),
    );
    final normalizedMirrorHost = mirrorHost?.toLowerCase();
    final trustedMirror =
        normalizedMirrorHost != null &&
        (host == normalizedMirrorHost ||
            host.endsWith('.$normalizedMirrorHost'));
    if (uri.scheme != 'https' || (!trustedGitHub && !trustedMirror)) {
      throw const OptionalPluginRepositoryException('插件下载地址不受信任');
    }
  }
}
