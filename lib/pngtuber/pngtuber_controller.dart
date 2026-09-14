import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../assets_path.dart';
import 'mouth_track.dart';
import 'adaptive_tone_mapper.dart';
import 'pcm_volume_analyzer.dart';
import 'pngtuber_math.dart';
import 'mouth_transition_gate.dart';
import 'video_playback_clock.dart';

class PNGTuberController extends ChangeNotifier {
  PNGTuberController();

  static const mouthTransitionDuration = Duration(milliseconds: 120);

  final AudioRecorder _recorder = AudioRecorder();
  final PcmVolumeAnalyzer _analyzer = PcmVolumeAnalyzer();
  final AdaptiveToneMapper _toneMapper = AdaptiveToneMapper();
  final VideoPlaybackClock _videoClock = VideoPlaybackClock();
  final MouthTransitionGate _mouthTransitionGate = MouthTransitionGate();
  final Map<MouthState, ui.Image> sprites = {};
  final ValueNotifier<int> renderSignal = ValueNotifier<int>(0);
  final ValueNotifier<double> volumeSignal = ValueNotifier<double>(0);
  final ValueNotifier<MouthState> mouthStateSignal = ValueNotifier<MouthState>(
    MouthState.closed,
  );

  VideoPlayerController? video;
  MouthTrackData? track;
  StreamSubscription<Uint8List>? _audioSubscription;
  MethodChannel? _nativeStageChannel;
  bool _nativePlaying = true;
  bool get usesNativeStage =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Timer? _frameTimer;
  Object? fatalError;
  String? statusMessage;
  bool loading = true;
  bool listening = false;
  double sensitivity = 50;
  double volume = 0;
  double _smoothedHighRatio = 0;
  double _envelope = 0;
  double _noiseFloor = 0.002;
  double _levelPeak = 0.02;
  double _mouthLevel = 0;
  MouthState mouthState = MouthState.closed;
  MouthState previousMouthState = MouthState.closed;
  DateTime _transitionStarted = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastObservedVideoPosition = Duration.zero;

  double get mouthBlend {
    if (previousMouthState == mouthState) return 1;
    final linear =
        (DateTime.now().difference(_transitionStarted).inMicroseconds /
                mouthTransitionDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    // Smoothstep has zero velocity at both ends, avoiding a visible pop when
    // the old sprite disappears or the new sprite reaches full opacity.
    return smoothStep(linear);
  }

  Set<MouthState> get availableStates => sprites.keys.toSet();
  MouthTrackFrame get renderFrame =>
      track!.frameAt(renderPosition, presentationTimestamp: false);
  Duration get renderPosition {
    if (usesNativeStage) return Duration.zero;
    final controller = video;
    if (controller == null) return Duration.zero;
    return _videoClock.positionAt(
      time: DateTime.now(),
      duration: controller.value.duration,
      playing: controller.value.isPlaying && !controller.value.isBuffering,
      speed: controller.value.playbackSpeed,
    );
  }

  bool get ready =>
      !loading &&
      fatalError == null &&
      (usesNativeStage || video?.value.isInitialized == true) &&
      track != null;

  bool get isVideoPlaying =>
      usesNativeStage ? _nativePlaying : video?.value.isPlaying == true;

  void attachNativeStage(int viewId) {
    final channel = MethodChannel('pngtuber/native-stage/$viewId');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'error') {
        final message = call.arguments?.toString() ?? 'Video playback failed.';
        statusMessage = 'Character video failed: $message';
        notifyListeners();
      }
      return null;
    });
    _nativeStageChannel = channel;
    unawaited(_sendNativeMouthState());
  }

  Future<void> _sendNativeMouthState() async {
    try {
      await _nativeStageChannel?.invokeMethod<void>(
        'setMouthState',
        <String, Object>{'state': mouthState.name},
      );
    } catch (_) {
      // The platform view may be in the process of being disposed.
    }
  }

  Future<void> initialize() async {
    try {
      track = MouthTrackData.decode(
        await rootBundle.loadString(AssetsPath.mouthTrack),
      );
      for (final state in MouthState.values) {
        try {
          final data = await rootBundle.load(
            AssetsPath.mouthSprite(state.name),
          );
          sprites[state] = await _decodeImage(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } on FlutterError {
          if (state == MouthState.closed || state == MouthState.open) rethrow;
        }
      }
      if (!sprites.containsKey(MouthState.closed) ||
          !sprites.containsKey(MouthState.open)) {
        throw StateError('closed.png and open.png are required.');
      }

      if (!usesNativeStage) {
        // Android uses the native stage so the video texture and mouth are
        // drawn in the same canvas pass. Other platforms retain video_player.
        final controller = VideoPlayerController.asset(
          AssetsPath.characterVideo,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        await controller.initialize();
        await controller.setLooping(true);
        await controller.setVolume(0);
        video = controller;
        controller.addListener(_handleVideoUpdate);
        await controller.play();
        final initialPosition = await controller.position ?? Duration.zero;
        _lastObservedVideoPosition = initialPosition;
        _videoClock.sync(initialPosition, DateTime.now());
        final frameInterval = Duration(
          microseconds: (Duration.microsecondsPerSecond / track!.fps).round(),
        );
        _frameTimer = Timer.periodic(
          frameInterval,
          (_) => renderSignal.value++,
        );
      }
    } catch (caught) {
      fatalError = caught;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  void _handleVideoUpdate() {
    final position = video?.value.position;
    if (position != null && position != _lastObservedVideoPosition) {
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
    }
  }

  void setSensitivity(double value) {
    sensitivity = value.clamp(0, 100);
    notifyListeners();
  }

  void setManualState(MouthState state) => _setMouthState(state, force: true);

  Future<void> toggleMicrophone() =>
      listening ? stopMicrophone() : startMicrophone();

  Future<void> startMicrophone() async {
    if (listening) return;
    statusMessage = null;
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission was not granted.');
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
          // Voice processing currently produces invalid timestamps on some
          // macOS input devices. Raw PCM is also better for amplitude tracking.
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        ),
      );
      _audioSubscription = stream.listen(
        _handleAudioChunk,
        onError: (Object caught) {
          statusMessage = 'Microphone stream failed: $caught';
          unawaited(stopMicrophone());
        },
        onDone: () {
          if (listening) {
            statusMessage = 'The microphone stream stopped unexpectedly.';
            listening = false;
            notifyListeners();
          }
        },
      );
      listening = true;
      statusMessage = null;
    } catch (caught) {
      statusMessage = '$caught';
      listening = false;
    }
    notifyListeners();
  }

  void _handleAudioChunk(Uint8List chunk) {
    for (final sample in _analyzer.add(chunk)) {
      _handleVolumeSample(sample);
    }
  }

  void _handleVolumeSample(VolumeSample sample) {
    final ratio = sample.high / (sample.low + sample.high + 1e-6);
    _smoothedHighRatio = _smoothedHighRatio * 0.75 + ratio * 0.25;
    // Fast attack keeps speech feeling immediate; slower release avoids
    // chatter between syllables.
    final attackOrRelease = sample.rms > _envelope ? 0.68 : 0.28;
    _envelope =
        _envelope * (1 - attackOrRelease) + sample.rms * attackOrRelease;

    if (_envelope < _noiseFloor) {
      _noiseFloor = _noiseFloor * 0.75 + _envelope * 0.25;
    } else {
      _noiseFloor = _noiseFloor * 0.99 + _envelope * 0.01;
    }
    _levelPeak = math.max(_envelope, _levelPeak * 0.985);
    _levelPeak = math.max(_levelPeak, _noiseFloor + 0.006);

    final normalizedSensitivity = sensitivity / 100;
    final gate = _noiseFloor + 0.002 + (1 - normalizedSensitivity) * 0.008;
    if (_envelope < gate) {
      volume = 0;
      _mouthLevel += (0 - _mouthLevel) * 0.3;
      _selectMouthState(0.5);
      _publishAudioUiAtMostEvery(const Duration(milliseconds: 80));
      return;
    }

    final rawLevel = ((_envelope - _noiseFloor) / (_levelPeak - _noiseFloor))
        .clamp(0.0, 1.0);
    final gain = 0.6 + normalizedSensitivity * 0.8;
    volume = (math.pow(rawLevel, 0.75) * gain).clamp(0.0, 1.0).toDouble();
    final opennessSmoothing = volume > _mouthLevel ? 0.18 : 0.3;
    _mouthLevel += (volume - _mouthLevel) * opennessSmoothing;
    _selectMouthState(_toneMapper.normalize(_smoothedHighRatio));
    _publishAudioUiAtMostEvery(const Duration(milliseconds: 80));
  }

  void _selectMouthState(double normalizedTone) {
    _setMouthState(
      selectMouthStateHq(
        level: _mouthLevel,
        highRatio: normalizedTone,
        thresholds: volumeThresholdsHq(sensitivity),
        currentState: mouthState,
        available: availableStates,
      ),
    );
  }

  void _publishAudioUiAtMostEvery(Duration interval) {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate) >= interval) {
      _lastUiUpdate = now;
      volumeSignal.value = volume;
    }
  }

  void _setMouthState(MouthState state, {bool force = false}) {
    final fallback = sprites.containsKey(state)
        ? state
        : sprites.containsKey(MouthState.open)
        ? MouthState.open
        : MouthState.closed;
    final now = DateTime.now();
    if (!force &&
        !_mouthTransitionGate.shouldAccept(
          current: mouthState,
          next: fallback,
          now: now,
        )) {
      return;
    }
    if (force || fallback != mouthState) {
      if (force) _mouthTransitionGate.forceAccept(now);
      previousMouthState = force ? fallback : mouthState;
      mouthState = fallback;
      _transitionStarted = now;
      mouthStateSignal.value = mouthState;
      renderSignal.value++;
      if (usesNativeStage) unawaited(_sendNativeMouthState());
    }
  }

  Future<void> stopMicrophone() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    listening = false;
    _resetAudio();
    notifyListeners();
  }

  void _resetAudio() {
    volume = 0;
    _envelope = 0;
    _noiseFloor = 0.002;
    _levelPeak = 0.02;
    _mouthLevel = 0;
    _smoothedHighRatio = 0;
    _analyzer.reset();
    _toneMapper.reset();
    volumeSignal.value = 0;
    _setMouthState(MouthState.closed, force: true);
  }

  Future<void> toggleVideo() async {
    if (usesNativeStage) {
      try {
        final playing = await _nativeStageChannel?.invokeMethod<bool>('toggle');
        if (playing != null) _nativePlaying = playing;
      } catch (caught) {
        statusMessage = 'Video control failed: $caught';
      }
      notifyListeners();
      return;
    }
    final controller = video;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      final position = await controller.position ?? controller.value.position;
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
    } else {
      final position = await controller.position ?? controller.value.position;
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
      await controller.play();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _nativeStageChannel?.setMethodCallHandler(null);
    renderSignal.dispose();
    volumeSignal.dispose();
    mouthStateSignal.dispose();
    video?.removeListener(_handleVideoUpdate);
    unawaited(_audioSubscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(video?.dispose());
    for (final image in sprites.values) {
      image.dispose();
    }
    super.dispose();
  }
}
