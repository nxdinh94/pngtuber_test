package com.example.me_pngtuber

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.SurfaceTexture
import android.net.Uri
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import kotlin.math.roundToInt

/**
 * Draws the video texture and the mouth sprite in one Android canvas pass.
 * This mirrors motionpngtuber's OpenCV loop: one displayed video frame selects
 * one quad, and that quad is composited before the frame is presented.
 */
@OptIn(UnstableApi::class)
class PngtuberPlatformView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    params: Map<String, Any?>,
) : PlatformView, TextureView.SurfaceTextureListener, Player.Listener,
    VideoFrameMetadataListener {

    private val textureView = TextureView(context)
    private val overlayView = MouthOverlayView(context)
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "pngtuber/native-stage/$viewId")
    private val player: ExoPlayer
    private val track: Track
    private val sprites: Map<String, Bitmap>
    private val baseAsset: String
    private val frameLock = Any()
    private val pendingPresentationTimes = ArrayDeque<Long>()
    private var lastPresentedPtsUs: Long? = null
    private var surface: Surface? = null
    private var disposed = false
    private var currentState = "closed"
    private var previousState = "closed"
    private var transitionStartedNs = 0L
    private var playing = true
    private var emotionPlaying = false
    private var mouthOverlayEnabled = true
    private var playerError: String? = null

    init {
        val asset = params["video"] as? String
            ?: error("pngtuber native stage requires a video asset")
        baseAsset = asset
        val trackAsset = params["track"] as? String
            ?: error("pngtuber native stage requires a track asset")
        track = Track(readAssetText(trackAsset))
        sprites = Track.STATES.associateWith { state ->
            decodeAsset(params["mouth/$state"] as? String
                ?: error("pngtuber native stage requires mouth/$state"))
        }

        textureView.surfaceTextureListener = this
        container.addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        container.addView(
            overlayView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        channel.setMethodCallHandler(::handleMethodCall)

        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(context))
            .build()
        mouthOverlayEnabled = usesMouthOverlay(asset)
        player.setMediaItem(MediaItem.fromUri(assetUri(asset)))
        player.repeatMode = Player.REPEAT_MODE_OFF
        player.volume = 0f
        player.addListener(this)
        player.setVideoFrameMetadataListener(this)
        player.prepare()
        player.playWhenReady = true
        playing = true
    }

    override fun getView(): View = container

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        player.clearVideoFrameMetadataListener(this)
        player.removeListener(this)
        player.release()
        surface?.release()
        surface = null
        textureView.surfaceTextureListener = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setMouthState" -> {
                setMouthState(call.argument<String>("state") ?: "closed")
                result.success(null)
                playerError?.let { channel.invokeMethod("error", it) }
            }
            "toggle" -> {
                if (player.isPlaying) {
                    player.pause()
                    playing = false
                } else if (player.playbackState == Player.STATE_ENDED && !emotionPlaying) {
                    // ExoPlayer does not restart an ended one-cycle item from
                    // play() alone. Treat a paused ended base cycle as a
                    // request to start the base asset at position zero.
                    mouthOverlayEnabled = usesMouthOverlay(baseAsset)
                    playAsset(baseAsset, true)
                } else {
                    player.play()
                    playing = true
                }
                result.success(playing)
                overlayView.invalidate()
            }
            "playBase" -> {
                emotionPlaying = false
                mouthOverlayEnabled = usesMouthOverlay(baseAsset)
                val shouldPlay = call.argument<Boolean>("play") ?: true
                playAsset(baseAsset, shouldPlay)
                result.success(shouldPlay)
            }
            "playEmotion" -> {
                val asset = call.argument<String>("video")
                    ?: return result.error("missing_video", "Emotion video is required", null)
                emotionPlaying = true
                mouthOverlayEnabled = usesMouthOverlay(asset)
                playAsset(asset, true)
                result.success(true)
            }
            "play" -> {
                player.play()
                playing = true
                result.success(null)
            }
            "pause" -> {
                player.pause()
                playing = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setMouthState(next: String) {
        val normalized = if (sprites.containsKey(next)) next else "closed"
        if (normalized == currentState) return
        previousState = currentState
        currentState = normalized
        transitionStartedNs = System.nanoTime()
        overlayView.postInvalidateOnAnimation()
    }

    override fun onVideoFrameAboutToBeRendered(
        presentationTimeUs: Long,
        releaseTimeNs: Long,
        format: androidx.media3.common.Format,
        mediaFormat: android.media.MediaFormat?,
    ) {
        synchronized(frameLock) {
            if (pendingPresentationTimes.size > 8) pendingPresentationTimes.removeFirst()
            pendingPresentationTimes.addLast(presentationTimeUs)
        }
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        surface?.release()
        surface = Surface(texture)
        player.setVideoSurface(surface)
        if (playing) player.play()
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        player.setVideoSurface(null)
        surface?.release()
        surface = null
        return true
    }

    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {
        val pts = synchronized(frameLock) {
            if (pendingPresentationTimes.isEmpty()) null
            else {
                val latest = pendingPresentationTimes.last()
                pendingPresentationTimes.clear()
                latest
            }
        } ?: lastPresentedPtsUs
        if (pts != null) {
            lastPresentedPtsUs = pts
            textureViewFrameIndex = track.frameIndexForPts(pts)
        } else {
            val timestampNs = texture.timestamp
            if (timestampNs >= 0L) textureViewFrameIndex = track.frameIndexForPts(timestampNs / 1_000L)
        }
        overlayView.postInvalidateOnAnimation()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        playing = isPlaying
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState != Player.STATE_ENDED || disposed) return
        playing = false
        if (emotionPlaying) {
            channel.invokeMethod("emotionEnded", null)
        } else {
            channel.invokeMethod("baseEnded", null)
        }
        overlayView.invalidate()
    }

    override fun onPlayerError(error: PlaybackException) {
        val message = "${error.errorCodeName}: ${error.message ?: "Video playback failed"}"
        playerError = message
        if (emotionPlaying) {
            emotionPlaying = false
            mouthOverlayEnabled = usesMouthOverlay(baseAsset)
        }
        channel.invokeMethod("error", message)
    }

    private fun drawMouth(canvas: Canvas) {
        if (disposed || !mouthOverlayEnabled) return
        val quad = track.quadAt(textureViewFrameIndex) ?: return
        val sx = textureView.width.toFloat() / track.width
        val sy = textureView.height.toFloat() / track.height
        val destination = FloatArray(8)
        quad.forEachIndexed { index, point ->
            destination[index * 2] = point.x * sx
            destination[index * 2 + 1] = point.y * sy
        }

        val now = System.nanoTime()
        val progress = if (transitionStartedNs == 0L) 1f
        else ((now - transitionStartedNs).toDouble() / 120_000_000.0)
            .coerceIn(0.0, 1.0).toFloat()
        val eased = progress * progress * (3f - 2f * progress)
        val old = sprites[previousState]
        val current = sprites[currentState] ?: return
        if (old != null && previousState != currentState && eased < 1f) {
            drawSprite(canvas, old, destination, ((1f - eased) * 255f).roundToInt())
            overlayView.postInvalidateOnAnimation()
        }
        drawSprite(canvas, current, destination, (eased * 255f).roundToInt())
    }

    private fun drawSprite(canvas: Canvas, bitmap: Bitmap, destination: FloatArray, alpha: Int) {
        val source = floatArrayOf(
            0f, 0f,
            (bitmap.width - 1).toFloat(), 0f,
            (bitmap.width - 1).toFloat(), (bitmap.height - 1).toFloat(),
            0f, (bitmap.height - 1).toFloat(),
        )
        val matrix = Matrix()
        if (!matrix.setPolyToPoly(source, 0, destination, 0, 4)) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        paint.alpha = alpha.coerceIn(0, 255)
        canvas.drawBitmap(bitmap, matrix, paint)
    }

    private fun readAssetText(asset: String): String =
        container.context.assets.open("flutter_assets/$asset").bufferedReader().use { it.readText() }

    private fun decodeAsset(asset: String): Bitmap =
        container.context.assets.open("flutter_assets/$asset").use { input ->
            BitmapFactory.decodeStream(input) ?: error("Unable to decode asset $asset")
        }

    private fun assetUri(asset: String): Uri {
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        return Uri.parse("asset:///$lookupKey")
    }

    private fun usesMouthOverlay(asset: String): Boolean =
        asset.substringAfterLast('/').lowercase().contains("_mouthless")

    private fun playAsset(asset: String, shouldPlay: Boolean) {
        synchronized(frameLock) {
            pendingPresentationTimes.clear()
        }
        lastPresentedPtsUs = null
        textureViewFrameIndex = 0
        playerError = null
        player.repeatMode = Player.REPEAT_MODE_OFF
        player.setMediaItem(MediaItem.fromUri(assetUri(asset)))
        player.prepare()
        player.playWhenReady = shouldPlay
        playing = shouldPlay
    }

    private inner class MouthOverlayView(context: Context) : View(context) {
        override fun onDraw(canvas: Canvas) {
            drawMouth(canvas)
        }
    }

    private var textureViewFrameIndex = 0

    private class Track(source: String) {
        data class Point(val x: Float, val y: Float)

        companion object {
            val STATES = listOf("closed", "half", "open", "e", "u")
        }

        val fps: Double
        val width: Float
        val height: Float
        private val quads: Array<Array<Point>>
        private val valid: BooleanArray

        init {
            val root = JSONObject(source)
            fps = root.getDouble("fps")
            width = root.getDouble("width").toFloat()
            height = root.getDouble("height").toFloat()
            val frames = root.getJSONArray("frames")
            quads = Array(frames.length()) { i ->
                val raw = frames.getJSONObject(i).getJSONArray("quad")
                Array(4) { j ->
                    val p = raw.getJSONArray(j)
                    Point(p.getDouble(0).toFloat(), p.getDouble(1).toFloat())
                }
            }
            valid = BooleanArray(frames.length()) { i -> frames.getJSONObject(i).getBoolean("valid") }
            for (i in valid.indices) {
                if (!valid[i]) quads[i] = quads[(i - 1 + quads.size) % quads.size]
            }
        }

        fun frameIndexForPts(ptsUs: Long): Int {
            val raw = (ptsUs.toDouble() * fps / 1_000_000.0).roundToInt()
            return ((raw % quads.size) + quads.size) % quads.size
        }

        fun quadAt(index: Int): Array<Point>? =
            if (quads.isEmpty()) null else quads[((index % quads.size) + quads.size) % quads.size]
    }
}
