# Me PNGTuber

An Android Flutter app that loops the supplied character video and drives a five-state mouth overlay from live microphone PCM audio. All lip-sync processing is local; there is no LLM, speech recognition, TTS, or network dependency.

## Run

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Tap the microphone button to request permission and start lip-sync. Open the tune button for sensitivity, manual mouth states, video playback, and view reset controls. Pinch or drag the character to zoom and reposition it.

## Runtime assets

All app assets live under `assets/`. The shipped files are in `assets/character/`: the silent H.264 mouthless loop, its synchronized JSON quad track, and `closed`, `half`, `open`, `e`, and `u` transparent mouth sprites. Their paths are centralized in `lib/assets_path.dart` and exposed through `AssetsPath`.

The original source videos, mouth sprites, and NPZ tracking files are in `assets/source/` for regeneration. They are not included in the Flutter asset bundle.

The launcher icon and splash screen are Flutter defaults for this development build.

## Android mouth synchronization

Android uses a native stage that draws the decoded video texture and the mouth
sprite in one Android canvas pass. The stage pairs each updated texture frame with
its decoded presentation timestamp, selects the matching quad, and maps the sprite
with the same perspective warp used by `motionpngtuber`. This keeps the face and
mouth on the same displayed frame. Other platforms retain the Flutter renderer.

The default bundled video, JSON track and five sprites match the `sexy_seven`
source set. Additional selectable character sets live under
`assets/characters/`.
The catalog currently includes `sexy_five`, `sexy_one`, `sexy_four`,
`sexy_eight`, `sexy_nine`, and `boy_one` in addition to the default
`sexy_seven` set.
The downloaded mouthless source is MPEG-4 Part 2; the bundled loop is re-encoded
as H.264 (`avc1`) for Android decoder compatibility.
The JSON already contains calibrated quads (`calibrationApplied: false` prevents
applying the recorded calibration again).
