import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/optional_feature.dart';
import '../domain/optional_plugin_manifest.dart';

typedef OptionalPluginProxyResolver = String Function(Uri uri);
typedef OptionalPluginDownloadProgress = void Function(int received, int total);

class OptionalPluginRepositoryException implements Exception {
  const OptionalPluginRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OptionalPluginRepository {
  OptionalPluginRepository({
    required OptionalPluginProxyResolver proxyResolver,
    Uri? manifestUri,
    Future<Directory> Function()? temporaryDirectory,
    HttpClient Function()? httpClientFactory,
  }) : _proxyResolver = proxyResolver,
       _manifestUri =
           manifestUri ?? Uri.parse(OptionalFeatureCatalog.manifestUrl),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final OptionalPluginProxyResolver _proxyResolver;
  final Uri _manifestUri;
  final Future<Directory> Function() _temporaryDirectory;
  final HttpClient Function() _httpClientFactory;

  static const int _maximumRedirects = 5;
  static const int _maximumManifestBytes = 2 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Set<String> _trustedHostSuffixes = <String>{
    'github.com',
    'githubusercontent.com',
  };

  Future<OptionalPluginManifest> loadManifest() async {
    final bytes = await _downloadBytes(
      _manifestUri,
      maximumBytes: _maximumManifestBytes,
    );
    return OptionalPluginManifest.parse(utf8.decode(bytes));
  }

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
    final client = _httpClientFactory();
    client.findProxy = _proxyResolver;
    try {
      final response = await _open(client, artifact.url);
      final expectedTotal = artifact.size;
      final responseTotal = response.contentLength;
      if (responseTotal > 0 && responseTotal != expectedTotal) {
        throw const OptionalPluginRepositoryException('插件包大小与发布清单不一致');
      }
      final sink = file.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      try {
        await for (final chunk in response.timeout(_requestTimeout)) {
          received += chunk.length;
          if (received > expectedTotal) {
            throw const OptionalPluginRepositoryException('插件包超过发布清单声明的大小');
          }
          sink.add(chunk);
          onProgress?.call(received, expectedTotal);
        }
      } finally {
        await sink.close();
      }
      if (received != expectedTotal) {
        throw OptionalPluginRepositoryException(
          '插件包下载不完整：$received / $expectedTotal',
        );
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != artifact.sha256) {
        throw const OptionalPluginRepositoryException('插件包校验失败');
      }
      return file;
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _downloadBytes(Uri uri, {required int maximumBytes}) async {
    final client = _httpClientFactory();
    client.findProxy = _proxyResolver;
    try {
      final response = await _open(client, uri);
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.timeout(_requestTimeout)) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw const OptionalPluginRepositoryException('插件清单过大');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri initialUri) async {
    var current = initialUri;
    for (var redirect = 0; redirect <= _maximumRedirects; redirect++) {
      _validateUri(current);
      final request = await client.getUrl(current).timeout(_requestTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Lightly-Plugin-Installer',
      );
      final response = await request.close().timeout(_requestTimeout);
      if (!response.isRedirect) {
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw OptionalPluginRepositoryException(
            '插件下载失败：HTTP ${response.statusCode}',
          );
        }
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null ||
          location.isEmpty ||
          redirect == _maximumRedirects) {
        throw const OptionalPluginRepositoryException('插件下载重定向无效');
      }
      current = current.resolve(location);
    }
    throw const OptionalPluginRepositoryException('插件下载重定向次数过多');
  }

  void _validateUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final trusted = _trustedHostSuffixes.any(
      (suffix) => host == suffix || host.endsWith('.$suffix'),
    );
    if (uri.scheme != 'https' || !trusted) {
      throw const OptionalPluginRepositoryException('插件下载地址不受信任');
    }
  }
}
