/// A complete runtime asset set for one selectable character.
class CharacterAsset {
  const CharacterAsset({
    required this.id,
    required this.displayName,
    required this.video,
    required this.track,
    required this.mouthDirectory,
    this.thumbnail,
  });

  final String id;
  final String displayName;
  final String video;
  final String track;
  final String mouthDirectory;
  final String? thumbnail;

  String mouthSprite(String state) => '$mouthDirectory/$state.png';
}

/// Paths and the built-in character catalog used by the PNGTuber app.
abstract final class AssetsPath {
  const AssetsPath._();

  static const defaultCharacter = CharacterAsset(
    id: 'sexy_seven',
    displayName: 'Sexy Seven',
    video: 'assets/character/loop_mouthless_h264.mp4',
    track: 'assets/character/mouth_track.json',
    mouthDirectory: 'assets/character/mouth',
  );

  static const sexyFive = CharacterAsset(
    id: 'sexy_five',
    displayName: 'Sexy Five',
    video: 'assets/characters/sexy_five/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_five/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_five/mouth',
    thumbnail: 'assets/characters/sexy_five/thumbnail.png',
  );

  static const sexyOne = CharacterAsset(
    id: 'sexy_one',
    displayName: 'Sexy One',
    video: 'assets/characters/sexy_one/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_one/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_one/mouth',
  );

  static const sexyFour = CharacterAsset(
    id: 'sexy_four',
    displayName: 'Sexy Four',
    video: 'assets/characters/sexy_four/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_four/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_four/mouth',
    thumbnail: 'assets/characters/sexy_four/thumbnail.png',
  );

  static const characters = <CharacterAsset>[
    defaultCharacter,
    sexyFive,
    sexyOne,
    sexyFour,
  ];

  // Keep the original names available to callers that only need the default.
  static final characterVideo = defaultCharacter.video;
  static final mouthTrack = defaultCharacter.track;
  static final mouthDirectory = defaultCharacter.mouthDirectory;

  static String mouthSprite(String state) =>
      defaultCharacter.mouthSprite(state);
}
