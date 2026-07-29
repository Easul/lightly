import 'dart:async';
import 'dart:io';

typedef BrowserDownloadProgressCallback =
    Future<void> Function(int bytesReceived, int totalBytes);
typedef BrowserDownloadRetryCallback =
    void Function(int retryNumber, int maxRetries);
typedef BrowserDownloadResponseValidator =
    void Function(HttpClientResponse response);
typedef BrowserDownloadOutputFileResolver =
    Future<File> Function(
      HttpClientResponse response,
      File currentFile,
      Uri finalUrl,
    );
typedef BrowserDownloadOutputFileChanged = Future<void> Function(File file);

class BrowserDownloadCancelledException implements Exception {
  const BrowserDownloadCancelledException();
}

class BrowserDownloadRejectedException implements Exception {
  const BrowserDownloadRejectedException(this.message);

  final String message;
}

class BrowserDownloadProtocolException implements Exception {
  const BrowserDownloadProtocolException(this.message);

  final String message;
}

class BrowserDownloadHttpStatusException implements Exception {
  const BrowserDownloadHttpStatusException(this.statusCode);

  final int statusCode;
}

class BrowserDownloadTransferResult {
  const BrowserDownloadTransferResult({
    required this.bytesReceived,
    required this.totalBytes,
    required this.outputFile,
  });

  final int bytesReceived;
  final int totalBytes;
  final File outputFile;
}

class BrowserDownloadTransfer {
  BrowserDownloadTransfer({
    required HttpClient client,
    int maxAttempts = 4,
    Duration idleTimeout = const Duration(seconds: 45),
    Duration Function(int completedAttempts)? retryDelay,
  }) : assert(maxAttempts > 0),
       _client = client,
       _maxAttempts = maxAttempts,
       _idleTimeout = idleTimeout,
       _retryDelay = retryDelay ?? _defaultRetryDelay;

  final HttpClient _client;
  final int _maxAttempts;
  final Duration _idleTimeout;
  final Duration Function(int completedAttempts) _retryDelay;
  final Completer<void> _cancelled = Completer<void>();
  final Completer<void> _done = Completer<void>();

  IOSink? _sink;
  bool _isCancelled = false;
  int _knownTotalBytes = 0;
  String? _entityValidator;
  File? _outputFile;

  Future<void> get done => _done.future;
  File? get outputFile => _outputFile;

  Future<void> cancel() async {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
    _client.close(force: true);
    await _closeSink();
  }

  Future<void> finish() async {
    await _closeSink();
    _client.close(force: true);
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<BrowserDownloadTransferResult> run({
    required Uri url,
    required File outputFile,
    required Map<String, String> requestHeaders,
    required int initialTotalBytes,
    required BrowserDownloadProgressCallback onProgress,
    required BrowserDownloadRetryCallback onRetry,
    required BrowserDownloadResponseValidator validateResponse,
    BrowserDownloadOutputFileResolver? resolveOutputFile,
    BrowserDownloadOutputFileChanged? onOutputFileChanged,
  }) async {
    _knownTotalBytes = initialTotalBytes > 0 ? initialTotalBytes : 0;
    _outputFile = outputFile;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      _throwIfCancelled();
      try {
        return await _runAttempt(
          url: url,
          requestHeaders: requestHeaders,
          onProgress: onProgress,
          validateResponse: validateResponse,
          resolveOutputFile: resolveOutputFile,
          onOutputFileChanged: onOutputFileChanged,
        );
      } catch (error) {
        await _closeSink();
        if (_isCancelled || error is BrowserDownloadCancelledException) {
          throw const BrowserDownloadCancelledException();
        }
        final retryable = _isRetryable(error);
        if (retryable) {
          await _persistCurrentFileLength(_outputFile!, onProgress);
        }
        if (!retryable || attempt >= _maxAttempts) {
          rethrow;
        }

        onRetry(attempt, _maxAttempts - 1);
        await Future.any<void>(<Future<void>>[
          Future<void>.delayed(_retryDelay(attempt)),
          _cancelled.future,
        ]);
      }
    }

    throw StateError('Download retry loop ended unexpectedly.');
  }

  Future<BrowserDownloadTransferResult> _runAttempt({
    required Uri url,
    required Map<String, String> requestHeaders,
    required BrowserDownloadProgressCallback onProgress,
    required BrowserDownloadResponseValidator validateResponse,
    required BrowserDownloadOutputFileResolver? resolveOutputFile,
    required BrowserDownloadOutputFileChanged? onOutputFileChanged,
  }) async {
    var outputFile = _outputFile!;
    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }

    var resumedFromBytes = await outputFile.exists()
        ? await outputFile.length()
        : 0;
    final opened = await _openWithSafeRedirects(
      url: url,
      requestHeaders: requestHeaders,
      resumedFromBytes: resumedFromBytes,
    );
    final response = opened.response;
    final finalUrl = opened.finalUrl;
    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
        resumedFromBytes > 0) {
      final serverTotal = _unsatisfiedRangeTotal(response);
      if (serverTotal != null && serverTotal == resumedFromBytes) {
        _knownTotalBytes = serverTotal;
        return BrowserDownloadTransferResult(
          bytesReceived: resumedFromBytes,
          totalBytes: serverTotal,
          outputFile: outputFile,
        );
      }
      if (serverTotal != null && resumedFromBytes > serverTotal) {
        await outputFile.writeAsBytes(const <int>[]);
        _entityValidator = null;
        throw HttpException(
          'Local partial file exceeds server length; restarting download',
          uri: url,
        );
      }
    }
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw BrowserDownloadHttpStatusException(response.statusCode);
    }

    validateResponse(response);
    final resolvedOutputFile = await resolveOutputFile?.call(
      response,
      outputFile,
      finalUrl,
    );
    if (resolvedOutputFile != null &&
        resolvedOutputFile.path != outputFile.path) {
      if (!await resolvedOutputFile.parent.exists()) {
        await resolvedOutputFile.parent.create(recursive: true);
      }
      if (await outputFile.exists()) {
        await outputFile.rename(resolvedOutputFile.path);
      }
      outputFile = resolvedOutputFile;
      _outputFile = outputFile;
      await onOutputFileChanged?.call(outputFile);
    }
    _captureEntityValidator(
      response,
      replaceMissing: response.statusCode == HttpStatus.ok,
    );

    var writeMode = FileMode.write;
    var bytesReceived = 0;
    if (response.statusCode == HttpStatus.partialContent) {
      final contentRange = _parseContentRange(response);
      if (contentRange == null || contentRange.start != resumedFromBytes) {
        throw BrowserDownloadProtocolException(
          'Invalid Content-Range start for resume at $resumedFromBytes',
        );
      }
      writeMode = FileMode.append;
      bytesReceived = resumedFromBytes;
      _knownTotalBytes = contentRange.totalBytes;
    } else {
      if (resumedFromBytes > 0) {
        await outputFile.writeAsBytes(const <int>[]);
        resumedFromBytes = 0;
      }
      _knownTotalBytes = response.contentLength > 0
          ? response.contentLength
          : _knownTotalBytes;
    }

    final sink = outputFile.openWrite(mode: writeMode);
    _sink = sink;
    var lastReportedBytes = bytesReceived;
    try {
      final responseStream = response.timeout(_idleTimeout);
      await for (final chunk in responseStream) {
        _throwIfCancelled();
        bytesReceived += chunk.length;
        sink.add(chunk);
        if (lastReportedBytes == 0 ||
            bytesReceived - lastReportedBytes >= 256 * 1024) {
          await onProgress(bytesReceived, _knownTotalBytes);
          lastReportedBytes = bytesReceived;
        }
      }
    } finally {
      await _closeSink(suppressErrors: false);
    }

    _throwIfCancelled();
    final fileLength = await outputFile.length();
    if (_knownTotalBytes > 0 && fileLength < _knownTotalBytes) {
      throw HttpException(
        'Download ended at $fileLength of $_knownTotalBytes bytes',
        uri: url,
      );
    }
    final totalBytes = _knownTotalBytes > fileLength
        ? _knownTotalBytes
        : fileLength;
    await onProgress(fileLength, totalBytes);
    return BrowserDownloadTransferResult(
      bytesReceived: fileLength,
      totalBytes: totalBytes,
      outputFile: outputFile,
    );
  }

  Future<({HttpClientResponse response, Uri finalUrl})> _openWithSafeRedirects({
    required Uri url,
    required Map<String, String> requestHeaders,
    required int resumedFromBytes,
  }) async {
    const maxRedirects = 5;
    const sensitiveHeaders = <String>{
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.refererHeader,
      'proxy-authorization',
    };
    var currentUrl = url;
    var headers = Map<String, String>.from(requestHeaders);

    for (var redirectCount = 0; ; redirectCount++) {
      _throwIfCancelled();
      if (!_isHttpUrl(currentUrl)) {
        throw BrowserDownloadProtocolException(
          'Unsupported download redirect scheme: ${currentUrl.scheme}',
        );
      }

      final request = await _client.getUrl(currentUrl);
      request.followRedirects = false;
      _applyRequestHeaders(request, headers);
      if (resumedFromBytes > 0) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=$resumedFromBytes-',
        );
        final validator = _entityValidator;
        if (validator != null && validator.isNotEmpty) {
          request.headers.set(HttpHeaders.ifRangeHeader, validator);
        }
      }

      final HttpClientResponse response;
      try {
        response = await request.close().timeout(_idleTimeout);
      } on TimeoutException {
        request.abort();
        rethrow;
      }
      if (!response.isRedirect) {
        return (response: response, finalUrl: currentUrl);
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        return (response: response, finalUrl: currentUrl);
      }
      if (redirectCount >= maxRedirects) {
        await response.drain<void>();
        throw const BrowserDownloadProtocolException(
          'Download exceeded the redirect limit',
        );
      }

      final nextUrl = currentUrl.resolve(location.trim());
      if (!_isHttpUrl(nextUrl)) {
        await response.drain<void>();
        throw BrowserDownloadProtocolException(
          'Unsupported download redirect scheme: ${nextUrl.scheme}',
        );
      }
      await response.drain<void>();
      if (!_hasSameOrigin(currentUrl, nextUrl)) {
        headers = <String, String>{
          for (final entry in headers.entries)
            if (!sensitiveHeaders.contains(entry.key.toLowerCase()))
              entry.key: entry.value,
        };
      }
      currentUrl = nextUrl;
    }
  }

  bool _isHttpUrl(Uri url) {
    final scheme = url.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && url.host.isNotEmpty;
  }

  bool _hasSameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        first.port == second.port;
  }

  void _applyRequestHeaders(
    HttpClientRequest request,
    Map<String, String> requestHeaders,
  ) {
    for (final header in requestHeaders.entries) {
      final value = header.value.trim();
      if (value.isNotEmpty &&
          header.key.toLowerCase() != HttpHeaders.rangeHeader &&
          header.key.toLowerCase() != HttpHeaders.ifRangeHeader) {
        request.headers.set(header.key, value);
      }
    }
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  }

  Future<void> _persistCurrentFileLength(
    File outputFile,
    BrowserDownloadProgressCallback onProgress,
  ) async {
    if (!await outputFile.exists()) {
      return;
    }
    await onProgress(await outputFile.length(), _knownTotalBytes);
  }

  void _captureEntityValidator(
    HttpClientResponse response, {
    required bool replaceMissing,
  }) {
    final etag = response.headers.value(HttpHeaders.etagHeader)?.trim();
    final lastModified = response.headers
        .value(HttpHeaders.lastModifiedHeader)
        ?.trim();
    final validator =
        etag != null && etag.isNotEmpty && !etag.toLowerCase().startsWith('w/')
        ? etag
        : lastModified?.isNotEmpty == true
        ? lastModified
        : null;
    if (validator != null || replaceMissing) {
      _entityValidator = validator;
    }
  }

  Future<void> _closeSink({bool suppressErrors = true}) async {
    final sink = _sink;
    _sink = null;
    if (sink == null) {
      return;
    }
    try {
      await sink.close();
    } catch (_) {
      if (!suppressErrors) {
        rethrow;
      }
    }
  }

  void _throwIfCancelled() {
    if (_isCancelled) {
      throw const BrowserDownloadCancelledException();
    }
  }

  bool _isRetryable(Object error) {
    if (error is BrowserDownloadHttpStatusException) {
      return error.statusCode == HttpStatus.requestTimeout ||
          error.statusCode == HttpStatus.tooManyRequests ||
          error.statusCode >= HttpStatus.internalServerError;
    }
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is HandshakeException;
  }

  _ContentRange? _parseContentRange(HttpClientResponse response) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    if (value == null) {
      return null;
    }
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final declaredTotal = match.group(3) == '*'
        ? null
        : int.tryParse(match.group(3)!);
    if (start == null || end == null || end < start) {
      return null;
    }
    final rangeLength = end - start + 1;
    if (response.contentLength >= 0 && response.contentLength != rangeLength) {
      return null;
    }
    final totalBytes = declaredTotal ?? start + rangeLength;
    if (totalBytes <= end) {
      return null;
    }
    return _ContentRange(start: start, totalBytes: totalBytes);
  }

  int? _unsatisfiedRangeTotal(HttpClientResponse response) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null
        ? null
        : RegExp(
            r'^bytes\s+\*/(\d+)$',
            caseSensitive: false,
          ).firstMatch(value.trim());
    return int.tryParse(match?.group(1) ?? '');
  }

  static Duration _defaultRetryDelay(int completedAttempts) {
    final seconds = switch (completedAttempts) {
      <= 1 => 1,
      2 => 2,
      _ => 4,
    };
    return Duration(seconds: seconds);
  }
}

class _ContentRange {
  const _ContentRange({required this.start, required this.totalBytes});

  final int start;
  final int totalBytes;
}
