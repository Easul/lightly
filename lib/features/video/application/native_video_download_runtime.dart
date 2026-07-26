class NativeVideoDownloadPrompt {
  const NativeVideoDownloadPrompt({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

enum NativeVideoDownloadStartResult { started, missingSavePath }

abstract interface class NativeVideoDownloadRuntime {
  String sanitizeFileName(String name);

  String resolveFileNameFromUrl(String url);

  Future<NativeVideoDownloadStartResult> startDownload({
    required String url,
    required String fileName,
    required void Function() onStarted,
    required void Function(String message) onStatus,
  });
}
