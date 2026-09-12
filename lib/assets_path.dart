/// Paths for assets used by the PNGTuber app.
abstract final class AssetsPath {
  const AssetsPath._();

  static const characterVideo = 'assets/character/loop_mouthless_h264.mp4';
  static const mouthTrack = 'assets/character/mouth_track.json';
  static const mouthDirectory = 'assets/character/mouth';

  static String mouthSprite(String state) => '$mouthDirectory/$state.png';
}
