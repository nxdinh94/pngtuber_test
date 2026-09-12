import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/video_playback_clock.dart';

void main() {
  final start = DateTime.utc(2026);

  test('advances continuously between sparse player position updates', () {
    final clock = VideoPlaybackClock()..sync(const Duration(seconds: 2), start);

    expect(
      clock.positionAt(
        time: start.add(const Duration(milliseconds: 33)),
        duration: const Duration(seconds: 10),
        playing: true,
      ),
      const Duration(milliseconds: 2033),
    );
  });

  test('wraps at the looping video duration', () {
    final clock = VideoPlaybackClock()
      ..sync(const Duration(milliseconds: 9980), start);

    expect(
      clock.positionAt(
        time: start.add(const Duration(milliseconds: 53)),
        duration: const Duration(seconds: 10),
        playing: true,
      ),
      const Duration(milliseconds: 33),
    );
  });

  test('holds the anchored position while paused', () {
    final clock = VideoPlaybackClock()..sync(const Duration(seconds: 4), start);

    expect(
      clock.positionAt(
        time: start.add(const Duration(seconds: 2)),
        duration: const Duration(seconds: 10),
        playing: false,
      ),
      const Duration(seconds: 4),
    );
  });
}
