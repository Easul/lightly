import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/infrastructure/remote_control_performance_monitor.dart';

void main() {
  test('samples video stats while preserving exact frame totals', () {
    final monitor = PerformanceMonitorService();
    monitor
      ..stopMonitoring()
      ..clear()
      ..startMonitoring();

    try {
      monitor.recordVideoFrame(frameSize: 100, isKeyFrame: false);
      for (var index = 0; index < 20; index++) {
        monitor.recordVideoFrame(frameSize: 1000, isKeyFrame: false);
      }

      var stats = monitor.getCurrentStats();
      var video = stats['video']! as Map<String, dynamic>;
      expect(video['totalFrames'], 21);
      expect(video['avgFrameSize'], 100);

      monitor.recordVideoFrame(frameSize: 500, isKeyFrame: true);
      stats = monitor.getCurrentStats();
      video = stats['video']! as Map<String, dynamic>;
      expect(video['totalFrames'], 22);
      expect(video['avgFrameSize'], 300);
    } finally {
      monitor
        ..stopMonitoring()
        ..clear();
    }
  });
}
