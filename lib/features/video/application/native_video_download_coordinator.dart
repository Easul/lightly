import 'native_video_download_runtime.dart';

String resolveNativeVideoDownloadFileName({
  required NativeVideoDownloadRuntime downloadRuntime,
  required String? resolvedTitle,
  required String? resolvedPlaybackUrl,
  required String originalVideoUrl,
}) {
  final title = resolvedTitle?.trim();
  if (title != null && title.isNotEmpty) {
    final hasExtension = RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(title);
    return downloadRuntime.sanitizeFileName(
      hasExtension ? title : '$title.mp4',
    );
  }
  return downloadRuntime.resolveFileNameFromUrl(
    resolvedPlaybackUrl ?? originalVideoUrl,
  );
}

typedef NativeVideoDownloadConfirmation =
    Future<String?> Function(NativeVideoDownloadPrompt prompt);

class NativeVideoDownloadCoordinator {
  const NativeVideoDownloadCoordinator({
    required NativeVideoDownloadRuntime downloadRuntime,
  }) : _downloadRuntime = downloadRuntime;

  final NativeVideoDownloadRuntime _downloadRuntime;

  Future<void> startDownload({
    required String playbackUrl,
    required String fileName,
    required NativeVideoDownloadConfirmation confirmDownload,
    required void Function(String message) onStatus,
  }) async {
    final prompt = NativeVideoDownloadPrompt(
      url: playbackUrl,
      fileName: fileName,
    );

    final confirmedFileName = await confirmDownload(prompt);
    if (confirmedFileName == null) {
      return;
    }

    final result = await _downloadRuntime.startDownload(
      url: playbackUrl,
      fileName: confirmedFileName,
      onStarted: () => onStatus('开始下载：$confirmedFileName'),
      onStatus: onStatus,
    );
    if (result == NativeVideoDownloadStartResult.missingSavePath) {
      onStatus('下载失败：无法确定保存路径');
    }
  }
}
