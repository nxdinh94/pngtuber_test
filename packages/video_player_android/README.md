# Local video_player_android 2.12.2

Vendored from the Flutter pub cache, retaining upstream LICENSE and AUTHORS.
The app overrides the Android package with this copy; other platforms use their
normal implementations.

Local change: `FramePresentationStream` attaches an ExoPlayer video frame metadata
listener for each player. `pngtuber/video_frames/<playerId>` publishes each media
presentation timestamp (microseconds) at its scheduled release time. The mouth
renderer holds that timestamp until the next decoded frame instead of advancing
an independent clock. This follows dropped frames, buffering and loop resets.
Callbacks and channels are removed when the player is disposed.

This reports decoder release, not a hardware display fence. Flutter composition
can still introduce a display-frame delay under load.
