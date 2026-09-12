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
