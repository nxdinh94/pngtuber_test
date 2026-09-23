import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/assets_path.dart';
import 'package:me_pngtuber/pngtuber/mouth_track.dart';
import 'package:me_pngtuber/pngtuber/pngtuber_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled character assets match the renderer contract', () async {
    expect(AssetsPath.characters, hasLength(10));
    for (final character in AssetsPath.characters) {
      final track = MouthTrackData.decode(
        await rootBundle.loadString(character.track),
      );

      expect(track.fps, greaterThan(0));
      expect(track.width, greaterThan(0));
      expect(track.height, greaterThan(0));
      expect(track.frames, isNotEmpty);
      expect(track.frames.every((frame) => frame.valid), isTrue);
      expect(track.refSpriteSize, const Size(128, 85));

      for (final state in MouthState.values) {
        final data = await rootBundle.load(character.mouthSprite(state.name));
        expect(data, isA<ByteData>());
        expect(data.lengthInBytes, greaterThan(0));
      }

      final video = await rootBundle.load(character.video);
      expect(video.lengthInBytes, greaterThan(0));

      if (character.thumbnail != null) {
        final thumbnail = await rootBundle.load(character.thumbnail!);
        expect(thumbnail.lengthInBytes, greaterThan(0));
      }

      for (final emotionalVideo in character.emotionalVideos) {
        final data = await rootBundle.load(emotionalVideo);
        expect(data.lengthInBytes, greaterThan(0));
      }
    }
  });

  test('sexy eight complete emotion videos do not use the mouth overlay', () {
    expect(AssetsPath.sexyEight.emotionalVideos, <String>[
      'assets/characters/sexy_eight/cry.mp4',
      'assets/characters/sexy_eight/laughing.mp4',
    ]);
    expect(
      AssetsPath.sexyEight.usesMouthOverlayFor(
        AssetsPath.sexyEight.emotionalVideos[0],
      ),
      isFalse,
    );
    expect(
      AssetsPath.sexyEight.usesMouthOverlayFor(
        AssetsPath.sexyEight.emotionalVideos[1],
      ),
      isFalse,
    );
    expect(
      AssetsPath.sexyEight.usesMouthOverlayFor(AssetsPath.sexyEight.video),
      isTrue,
    );
  });

  test('sexy five character is present in the girl tab catalog', () {
    final girlCharacters = AssetsPath.characters
        .where((c) => c.gender == CharacterGender.girl)
        .toList();
    expect(girlCharacters.any((c) => c.id == 'sexy_five'), isTrue);
    expect(AssetsPath.sexyFive.gender, CharacterGender.girl);
    expect(AssetsPath.sexyFive.displayName, 'Sexy Five');
    expect(AssetsPath.sexyFive.thumbnail, 'assets/characters/sexy_five/thumbnail.png');
  });

  test('sexy two character is present in the girl tab catalog', () {
    final girlCharacters = AssetsPath.characters
        .where((c) => c.gender == CharacterGender.girl)
        .toList();
    expect(girlCharacters.any((c) => c.id == 'sexy_two'), isTrue);
    expect(AssetsPath.sexyTwo.gender, CharacterGender.girl);
    expect(AssetsPath.sexyTwo.displayName, 'Sexy Two');
    expect(
      AssetsPath.sexyTwo.thumbnail,
      'assets/characters/sexy_two/thumbnail.png',
    );
  });

  test('sexy three character is present in the girl tab catalog', () {
    final girlCharacters = AssetsPath.characters
        .where((c) => c.gender == CharacterGender.girl)
        .toList();
    expect(girlCharacters.any((c) => c.id == 'sexy_three'), isTrue);
    expect(AssetsPath.sexyThree.gender, CharacterGender.girl);
    expect(AssetsPath.sexyThree.displayName, 'Sexy Three');
    expect(
      AssetsPath.sexyThree.thumbnail,
      'assets/characters/sexy_three/thumbnail.jpeg',
    );
  });
}
