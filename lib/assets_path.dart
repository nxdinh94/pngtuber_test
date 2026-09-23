enum CharacterGender { girl, boy }

/// A complete runtime asset set for one selectable character.
class CharacterAsset {
  const CharacterAsset({
    required this.id,
    required this.displayName,
    required this.gender,
    required this.video,
    required this.track,
    required this.mouthDirectory,
    this.emotionalVideos = const [],
    this.thumbnail,
  });

  final String id;
  final String displayName;
  final CharacterGender gender;
  final String video;
  final String track;
  final String mouthDirectory;
  final List<String> emotionalVideos;
  final String? thumbnail;

  String mouthSprite(String state) => '$mouthDirectory/$state.png';

  bool usesMouthOverlayFor(String videoPath) {
    final fileName = videoPath.replaceAll('\\', '/').split('/').last;
    return fileName.toLowerCase().contains('_mouthless');
  }
}

/// Paths and the built-in character catalog used by the PNGTuber app.
abstract final class AssetsPath {
  const AssetsPath._();

  static const defaultCharacter = CharacterAsset(
    id: 'sexy_seven',
    displayName: 'Sexy Seven',
    gender: CharacterGender.girl,
    video: 'assets/character/loop_mouthless_h264.mp4',
    track: 'assets/character/mouth_track.json',
    mouthDirectory: 'assets/character/mouth',
  );

  static const sexyFive = CharacterAsset(
    id: 'sexy_five',
    displayName: 'Sexy Five',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_five/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_five/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_five/mouth',
    thumbnail: 'assets/characters/sexy_five/thumbnail.png',
  );

  static const sexyOne = CharacterAsset(
    id: 'sexy_one',
    displayName: 'Sexy One',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_one/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_one/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_one/mouth',
  );

  static const sexyTwo = CharacterAsset(
    id: 'sexy_two',
    displayName: 'Sexy Two',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_two/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_two/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_two/mouth',
    thumbnail: 'assets/characters/sexy_two/thumbnail.png',
  );

  static const sexyThree = CharacterAsset(
    id: 'sexy_three',
    displayName: 'Sexy Three',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_three/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_three/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_three/mouth',
    thumbnail: 'assets/characters/sexy_three/thumbnail.jpeg',
  );

  static const sexyFour = CharacterAsset(
    id: 'sexy_four',
    displayName: 'Sexy Four',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_four/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_four/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_four/mouth',
    thumbnail: 'assets/characters/sexy_four/thumbnail.png',
  );

  static const sexyEight = CharacterAsset(
    id: 'sexy_eight',
    displayName: 'Sexy Eight',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_eight/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_eight/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_eight/mouth',
    emotionalVideos: <String>[
      'assets/characters/sexy_eight/cry.mp4',
      'assets/characters/sexy_eight/laughing.mp4',
    ],
    thumbnail: 'assets/characters/sexy_eight/thumbnail.png',
  );

  static const sexyNine = CharacterAsset(
    id: 'sexy_nine',
    displayName: 'Sexy Nine',
    gender: CharacterGender.girl,
    video: 'assets/characters/sexy_nine/loop_mouthless_h264.mp4',
    track: 'assets/characters/sexy_nine/mouth_track.json',
    mouthDirectory: 'assets/characters/sexy_nine/mouth',
    thumbnail: 'assets/characters/sexy_nine/thumbnail.png',
  );

  static const boyOne = CharacterAsset(
    id: 'boy_one',
    displayName: 'Boy One',
    gender: CharacterGender.boy,
    video: 'assets/characters/boy_one/loop_mouthless_h264.mp4',
    track: 'assets/characters/boy_one/mouth_track.json',
    mouthDirectory: 'assets/characters/boy_one/mouth',
    thumbnail: 'assets/characters/boy_one/thumbnail.png',
  );

  static const boyThree = CharacterAsset(
    id: 'boy_three',
    displayName: 'Boy Three',
    gender: CharacterGender.boy,
    video: 'assets/characters/boy_three/loop_mouthless_h264.mp4',
    track: 'assets/characters/boy_three/mouth_track.json',
    mouthDirectory: 'assets/characters/boy_three/mouth',
    thumbnail: 'assets/characters/boy_three/thumbnail.png',
  );

  static const characters = <CharacterAsset>[
    defaultCharacter,
    sexyFive,
    sexyOne,
    sexyTwo,
    sexyThree,
    sexyFour,
    sexyEight,
    sexyNine,
    boyOne,
    boyThree,
  ];

  // Keep the original names available to callers that only need the default.
  static final characterVideo = defaultCharacter.video;
  static final mouthTrack = defaultCharacter.track;
  static final mouthDirectory = defaultCharacter.mouthDirectory;

  static String mouthSprite(String state) =>
      defaultCharacter.mouthSprite(state);
}
