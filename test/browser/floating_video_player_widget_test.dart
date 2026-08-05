import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/domain/floating_video_system_ui_runtime.dart';
import 'package:lightly/features/video/presentation/widgets/floating_video_player.dart';
import 'package:lightly/features/video/presentation/widgets/floating_video_player_widget.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('mini video player shows only the close control', (tester) async {
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 100,
              child: FloatingVideoPlayerWidget(
                mode: FloatingPlayerMode.mini,
                isLoading: true,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen), findsNothing);
    expect(find.byIcon(Icons.lock_open), findsNothing);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });

  testWidgets('surface gestures seek and temporarily change playback speed', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    var centerDoubleTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 225,
              child: FloatingVideoPlayerWidget(
                controller: controller,
                mode: FloatingPlayerMode.defaultMode,
                onCenterDoubleTap: () => centerDoubleTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byType(FloatingVideoPlayerWidget);
    final origin = tester.getTopLeft(surface);

    await tester.tapAt(origin + const Offset(40, 112));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(origin + const Offset(40, 112));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      controller.seekTargets.last,
      const Duration(minutes: 4, seconds: 55),
    );

    await tester.tapAt(origin + const Offset(200, 112));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(origin + const Offset(200, 112));
    await tester.pump(const Duration(milliseconds: 400));
    expect(centerDoubleTaps, 1);

    await tester.tapAt(origin + const Offset(360, 112));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(origin + const Offset(360, 112));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.seekTargets.last, const Duration(minutes: 5));

    await tester.dragFrom(
      origin + const Offset(100, 112),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(
      controller.seekTargets.last,
      const Duration(minutes: 5, seconds: 15),
    );

    await tester.longPressAt(origin + const Offset(100, 112));
    await tester.pump();
    expect(controller.playbackSpeeds, containsAllInOrder(<double>[3.0, 1.0]));
  });

  testWidgets('double tapping mini player restores the default player', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final playerController = FloatingVideoPlayerController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingVideoPlayer(
                controller: controller,
                playerController: playerController,
                systemUiRuntime: _FakeFloatingVideoSystemUiRuntime(),
                onClose: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byType(FloatingVideoPlayerWidget);
    await tester.tapAt(tester.getCenter(surface));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getCenter(surface));
    await tester.pumpAndSettle();

    expect(playerController.mode, FloatingPlayerMode.mini);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tapAt(tester.getCenter(surface));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getCenter(surface));
    await tester.pumpAndSettle();

    expect(playerController.mode, FloatingPlayerMode.defaultMode);
    expect(find.byType(Slider), findsOneWidget);
  });
}

class _FakeFloatingVideoSystemUiRuntime
    implements FloatingVideoSystemUiRuntime {
  @override
  Future<void> setKeepScreenOn(bool keepOn) async {}
}

class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController() : super.asset('fake.mp4') {
    value = const VideoPlayerValue(
      duration: Duration(minutes: 10),
      position: Duration(minutes: 5),
      size: Size(16, 9),
      isInitialized: true,
      isPlaying: true,
    );
  }

  final List<Duration> seekTargets = <Duration>[];
  final List<double> playbackSpeeds = <double>[];

  @override
  Future<void> seekTo(Duration position) async {
    seekTargets.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeeds.add(speed);
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }
}
