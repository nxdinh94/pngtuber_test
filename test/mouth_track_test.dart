import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/mouth_track.dart';

void main() {
  const json = '''
  {
    "fps": 2,
    "width": 100,
    "height": 200,
    "refSpriteSize": [20, 10],
    "calibration": {"offset": [0, 0], "scale": 1, "rotation": 0},
    "calibrationApplied": false,
    "frames": [
      {"quad": [[0,0],[1,0],[1,1],[0,1]], "valid": true},
      {"quad": [[2,2],[3,2],[3,3],[2,3]], "valid": false}
    ]
  }
  ''';

  test('parses and synchronizes frames to video time', () {
    final track = MouthTrackData.decode(json);
    expect(track.frames, hasLength(2));
    expect(track.frameAt(const Duration(milliseconds: 100)).valid, isTrue);
    expect(track.frameAt(const Duration(milliseconds: 600)).valid, isFalse);
    expect(track.frameAt(const Duration(milliseconds: 1100)).valid, isTrue);
  });

  test('rejects malformed quads', () {
    expect(
      () => MouthTrackData.decode(
        json.replaceFirst('[[0,0],[1,0],[1,1],[0,1]]', '[[0,0]]'),
      ),
      throwsFormatException,
    );
  });

  test('decoder timestamps select the correct 24 fps quad across a loop', () {
    final track = MouthTrackData.decode(
      json.replaceFirst('"fps": 2', '"fps": 24'),
    );
    for (final us in [41666, 41667]) {
      expect(
        track.frameAt(Duration(microseconds: us), presentationTimestamp: true),
        same(track.frames[1]),
      );
    }
    expect(
      track.frameAt(Duration.zero, presentationTimestamp: true),
      same(track.frames[0]),
    );
    expect(
      track.frameAt(
        const Duration(microseconds: 83333),
        presentationTimestamp: true,
      ),
      same(track.frames[0]),
    );
  });
}
