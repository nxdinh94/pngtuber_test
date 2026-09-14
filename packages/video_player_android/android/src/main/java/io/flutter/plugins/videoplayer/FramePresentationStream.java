package io.flutter.plugins.videoplayer;

import android.os.Handler;
import android.os.Looper;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.video.VideoFrameMetadataListener;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;

/** Reports rendered media timestamps, holding position when the decoder stalls. */
@UnstableApi
final class FramePresentationStream implements EventChannel.StreamHandler {
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final EventChannel channel;
  private final ExoPlayer player;
  private EventChannel.EventSink sink;
  private volatile boolean disposed;
  private Long latestPositionUs;
  private final VideoFrameMetadataListener listener;

  FramePresentationStream(BinaryMessenger messenger, String id, ExoPlayer player) {
    this.player = player;
    channel = new EventChannel(messenger, "pngtuber/video_frames/" + id);
    channel.setStreamHandler(this);
    listener = (presentationTimeUs, releaseTimeNs, format, mediaFormat) -> {
      // The callback runs on the playback thread BEFORE release. Wait for the
      // scheduled release, then publish on the platform thread. Do not use the
      // playback position: it advances even when the displayed frame does not.
      long delayMs = Math.max(0, (releaseTimeNs - System.nanoTime()) / 1_000_000);
      if (!disposed) {
        handler.postDelayed(() -> {
          if (disposed) return;
          latestPositionUs = presentationTimeUs;
          if (sink != null) sink.success(presentationTimeUs);
        }, delayMs);
      }
    };
    player.setVideoFrameMetadataListener(listener);
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    sink = events;
    if (latestPositionUs != null) events.success(latestPositionUs);
  }

  @Override
  public void onCancel(Object arguments) {
    sink = null;
  }

  void dispose() {
    disposed = true;
    player.clearVideoFrameMetadataListener(listener);
    handler.removeCallbacksAndMessages(null);
    sink = null;
    channel.setStreamHandler(null);
  }
}
