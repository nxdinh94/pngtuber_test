import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/assets_path.dart';
import 'package:me_pngtuber/pngtuber/mouth_track.dart';
import 'package:me_pngtuber/pngtuber/pngtuber_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled character assets match the renderer contract', () async {
    final track = MouthTrackData.decode(
      await rootBundle.loadString(AssetsPath.mouthTrack),
    );

    expect(track.fps, 24);
    expect(track.width, greaterThan(0));
    expect(track.height, greaterThan(0));
    expect(track.frames, isNotEmpty);
    expect(track.frames.every((frame) => frame.valid), isTrue);
    expect(track.refSpriteSize, const Size(128, 85));

    for (final state in MouthState.values) {
      final data = await rootBundle.load(AssetsPath.mouthSprite(state.name));
      expect(data, isA<ByteData>());
      expect(data.lengthInBytes, greaterThan(0));
    }

    final video = await rootBundle.load(AssetsPath.characterVideo);
    expect(video.lengthInBytes, greaterThan(0));
  });
}
