package io.flutter.plugins.videoplayer;

import static org.mockito.Mockito.*;

import androidx.media3.common.Format;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.video.VideoFrameMetadataListener;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
public class FramePresentationStreamTest {
  @Test
  public void reportsFramesAndLoopResetWithoutAdvancingDuringStall() {
    ExoPlayer player = mock(ExoPlayer.class);
    FramePresentationStream stream = new FramePresentationStream(mock(BinaryMessenger.class), "1", player);
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    stream.onListen(null, sink);
    ArgumentCaptor<VideoFrameMetadataListener> callback = ArgumentCaptor.forClass(VideoFrameMetadataListener.class);
    verify(player).setVideoFrameMetadataListener(callback.capture());
    callback.getValue().onVideoFrameAboutToBeRendered(9958333L, System.nanoTime(), new Format.Builder().build(), null);
    ShadowLooper.idleMainLooper();
    verify(sink).success(9958333L);
    ShadowLooper.idleMainLooper();
    verifyNoMoreInteractions(sink);
    callback.getValue().onVideoFrameAboutToBeRendered(0L, System.nanoTime(), new Format.Builder().build(), null);
    ShadowLooper.idleMainLooper();
    verify(sink).success(0L);
    stream.dispose();
  }

  @Test
  public void lateSubscriberReceivesLastFrameAndDisposalCancelsPendingFrame() {
    ExoPlayer player = mock(ExoPlayer.class);
    FramePresentationStream stream = new FramePresentationStream(mock(BinaryMessenger.class), "2", player);
    ArgumentCaptor<VideoFrameMetadataListener> callback = ArgumentCaptor.forClass(VideoFrameMetadataListener.class);
    verify(player).setVideoFrameMetadataListener(callback.capture());
    callback.getValue().onVideoFrameAboutToBeRendered(41666L, System.nanoTime(), new Format.Builder().build(), null);
    ShadowLooper.idleMainLooper();
    EventChannel.EventSink sink = mock(EventChannel.EventSink.class);
    stream.onListen(null, sink);
    verify(sink).success(41666L);
    callback.getValue().onVideoFrameAboutToBeRendered(83333L, System.nanoTime() + 1_000_000_000L, new Format.Builder().build(), null);
    stream.dispose();
    ShadowLooper.runUiThreadTasksIncludingDelayedTasks();
    verifyNoMoreInteractions(sink);
    verify(player).clearVideoFrameMetadataListener(callback.getValue());
  }
}
