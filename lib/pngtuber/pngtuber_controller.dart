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
import 'emotion_cycle.dart';
import 'pcm_volume_analyzer.dart';
import 'pngtuber_math.dart';
import 'mouth_transition_gate.dart';
import 'video_playback_clock.dart';

class PNGTuberController extends ChangeNotifier {
  PNGTuberController({CharacterAsset? initialCharacter})
    : character = initialCharacter ?? AssetsPath.defaultCharacter;

  static const mouthTransitionDuration = Duration(milliseconds: 120);
  // The volume analyzer reports roughly 60 samples per second. Short onset
  // and release windows filter single noisy samples and normal gaps between
  // syllables without adding a user-visible emotion delay.
  static const _speechSamplesBeforeStart = 3;
  static const _quietSamplesBeforeSilence = 12;

  final AudioRecorder _recorder = AudioRecorder();
  final PcmVolumeAnalyzer _analyzer = PcmVolumeAnalyzer();
  final AdaptiveToneMapper _toneMapper = AdaptiveToneMapper();
  final VideoPlaybackClock _videoClock = VideoPlaybackClock();
  final MouthTransitionGate _mouthTransitionGate = MouthTransitionGate();
  final EmotionCycleState _emotionCycle = EmotionCycleState();
  final math.Random _random = math.Random();
  final Map<MouthState, ui.Image> sprites = {};
  final ValueNotifier<int> renderSignal = ValueNotifier<int>(0);
  final ValueNotifier<double> volumeSignal = ValueNotifier<double>(0);
  final ValueNotifier<MouthState> mouthStateSignal = ValueNotifier<MouthState>(
    MouthState.closed,
  );

  CharacterAsset character;
  VideoPlayerController? video;
  VideoPlayerController? _baseVideo;
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
  bool _videoPlaybackEnabled = true;
  bool _speechActive = false;
  bool _emotionPlaying = false;
  bool _emotionTransitioning = false;
  bool _emotionCompletionHandled = false;
  bool _baseCompletionHandled = false;
  bool _baseCycleWaitingForSilence = false;
  bool _returningToBase = false;
  bool _disposed = false;
  bool _baseListenerAttached = false;
  int _playbackToken = 0;
  String? _lastEmotionVideo;
  String? _activeVideoAsset;
  bool _activeVideoUsesMouthOverlay = true;
  double sensitivity = 50;
  double volume = 0;
  double _smoothedHighRatio = 0;
  double _envelope = 0;
  double _noiseFloor = 0.002;
  double _levelPeak = 0.02;
  double _mouthLevel = 0;
  int _loudSpeechSamples = 0;
  int _quietSpeechSamples = 0;
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
  bool get isEmotionPlaying => _emotionPlaying;
  String? get activeVideoAsset => _activeVideoAsset;
  bool get activeVideoUsesMouthOverlay => _activeVideoUsesMouthOverlay;

  void attachNativeStage(int viewId) {
    final channel = MethodChannel('pngtuber/native-stage/$viewId');
    channel.setMethodCallHandler((call) async {
      if (_nativeStageChannel != channel) return null;
      if (call.method == 'error') {
        final message = call.arguments?.toString() ?? 'Video playback failed.';
        statusMessage = 'Character video failed: $message';
        notifyListeners();
        if (_emotionPlaying || _emotionTransitioning) {
          unawaited(_returnToBaseVideo(cancelPending: true));
        } else {
          _cancelPlaybackState();
        }
      } else if (call.method == 'baseEnded') {
        unawaited(_handleBaseCycleCompleted());
      } else if (call.method == 'emotionEnded') {
        unawaited(_handleEmotionCompleted());
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

  Future<void> selectCharacter(CharacterAsset next) async {
    if (next.id == character.id || loading) return;

    _cancelPlaybackState();
    loading = true;
    fatalError = null;
    statusMessage = null;
    _frameTimer?.cancel();
    _frameTimer = null;

    final oldVideo = video;
    final oldBaseVideo = _baseVideo;
    video = null;
    _baseVideo = null;
    oldVideo?.removeListener(_handleVideoUpdate);
    if (oldBaseVideo != null && oldBaseVideo != oldVideo) {
      oldBaseVideo.removeListener(_handleVideoUpdate);
    }
    if (_baseListenerAttached) _baseListenerAttached = false;
    await oldVideo?.dispose();
    if (oldBaseVideo != null && oldBaseVideo != oldVideo) {
      await oldBaseVideo.dispose();
    }

    _nativeStageChannel?.setMethodCallHandler(null);
    _nativeStageChannel = null;
    _nativePlaying = true;
    _videoPlaybackEnabled = true;
    for (final image in sprites.values) {
      image.dispose();
    }
    sprites.clear();
    track = null;
    character = next;
    _activeVideoAsset = null;
    _activeVideoUsesMouthOverlay = true;
    _lastEmotionVideo = null;
    mouthState = MouthState.closed;
    previousMouthState = MouthState.closed;
    mouthStateSignal.value = MouthState.closed;
    renderSignal.value++;
    notifyListeners();

    await initialize();
    _updateEmotionEnabled();
  }

  Future<void> initialize() async {
    VideoPlayerController? createdVideo;
    try {
      track = MouthTrackData.decode(
        await rootBundle.loadString(character.track),
      );
      for (final state in MouthState.values) {
        try {
          final data = await rootBundle.load(character.mouthSprite(state.name));
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

      _activeVideoAsset = character.video;
      _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
        character.video,
      );

      if (!usesNativeStage) {
        // Android uses the native stage so the video texture and mouth are
        // drawn in the same canvas pass. Other platforms retain video_player.
        final controller = VideoPlayerController.asset(
          character.video,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        createdVideo = controller;
        await controller.initialize();
        await controller.setLooping(false);
        await controller.setVolume(0);
        _baseVideo = controller;
        video = controller;
        _activeVideoAsset = character.video;
        _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
          character.video,
        );
        _baseCompletionHandled = false;
        controller.addListener(_handleVideoUpdate);
        _baseListenerAttached = true;
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
      if (createdVideo != null && createdVideo != video) {
        await createdVideo.dispose();
      }
      fatalError = caught;
    } finally {
      loading = false;
      _updateEmotionEnabled();
      notifyListeners();
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  void _handleVideoUpdate() {
    final currentVideo = video;
    if (currentVideo == null) return;
    if (currentVideo.value.hasError) {
      final emotionActive = _emotionPlaying || _emotionTransitioning;
      statusMessage =
          'Character video failed: '
          '${currentVideo.value.errorDescription ?? 'Video playback failed.'}';
      if (emotionActive) {
        unawaited(_returnToBaseVideo(cancelPending: true));
      } else {
        _cancelPlaybackState();
      }
      notifyListeners();
      return;
    }
    final position = currentVideo.value.position;
    if (position != _lastObservedVideoPosition) {
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
    }
    if (currentVideo == _baseVideo &&
        currentVideo.value.isCompleted &&
        !_baseCompletionHandled) {
      unawaited(_handleBaseCycleCompleted());
    } else if (currentVideo != _baseVideo &&
        _emotionPlaying &&
        !_emotionCompletionHandled &&
        currentVideo.value.isCompleted) {
      _emotionCompletionHandled = true;
      unawaited(_handleEmotionCompleted());
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
            _speechActive = false;
            _emotionCycle.microphoneStopped();
            if (_baseCycleWaitingForSilence) {
              _baseCycleWaitingForSilence = false;
              _baseCompletionHandled = false;
              unawaited(_handleBaseCycleCompleted());
            }
            notifyListeners();
          }
        },
      );
      listening = true;
      _updateEmotionEnabled();
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
    if (_envelope >= gate) {
      _quietSpeechSamples = 0;
      _loudSpeechSamples++;
      if (_loudSpeechSamples >= _speechSamplesBeforeStart) {
        _updateSpeechActivity(true);
        if (_baseCycleWaitingForSilence) {
          _baseCycleWaitingForSilence = false;
          _baseCompletionHandled = false;
          _emotionCycle.cancelPending();
          unawaited(_restartBaseVideo());
        }
      }
    } else {
      _loudSpeechSamples = 0;
      _quietSpeechSamples++;
      if (_quietSpeechSamples >= _quietSamplesBeforeSilence) {
        _updateSpeechActivity(false);
        if (_baseCycleWaitingForSilence && !_speechActive) {
          _baseCycleWaitingForSilence = false;
          _baseCompletionHandled = false;
          unawaited(_handleBaseCycleCompleted());
        }
      }
    }
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
    listening = false;
    _speechActive = false;
    _emotionCycle.microphoneStopped();
    if (_baseCycleWaitingForSilence) {
      _baseCycleWaitingForSilence = false;
      _baseCompletionHandled = false;
      unawaited(_handleBaseCycleCompleted());
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    _resetAudio();
    notifyListeners();
  }

  void _updateSpeechActivity(bool speaking) {
    if (speaking) {
      if (_speechActive) return;
      _speechActive = true;
      _emotionCycle.speechStarted();
      return;
    }

    if (_speechActive) {
      _speechActive = false;
      _emotionCycle.silenceDetected();
    }
  }

  void _updateEmotionEnabled() {
    _emotionCycle.setEnabled(
      _videoPlaybackEnabled && character.emotionalVideos.isNotEmpty,
    );
  }

  Future<void> _handleBaseCycleCompleted() async {
    if (_disposed ||
        !_videoPlaybackEnabled ||
        _emotionPlaying ||
        _emotionTransitioning) {
      return;
    }
    if (_baseCompletionHandled) return;
    _baseCompletionHandled = true;
    // A pending request can only be consumed while the microphone still
    // considers the user silent. This second guard protects the exact cycle
    // boundary from a speech sample arriving just after the pending flag was
    // set.
    if (_speechActive) {
      if (_quietSpeechSamples > 0) {
        // The base ended during the short speech-release window. Hold the
        // completed boundary until silence is confirmed or speech resumes.
        _baseCycleWaitingForSilence = true;
      } else {
        _emotionCycle.cancelPending();
        await _restartBaseVideo();
      }
      return;
    }
    if (_emotionCycle.consumeEmotionAtBaseCycleEnd()) {
      await _playRandomEmotion();
    } else {
      await _restartBaseVideo();
    }
  }

  Future<void> _restartBaseVideo() async {
    if (_disposed || !_videoPlaybackEnabled) return;
    _baseCycleWaitingForSilence = false;
    if (usesNativeStage) {
      try {
        await _nativeStageChannel?.invokeMethod<bool>(
          'playBase',
          <String, Object>{'play': true},
        );
      } catch (caught) {
        statusMessage = 'Restarting the base video failed: $caught';
      }
      _baseCompletionHandled = false;
      _activeVideoAsset = character.video;
      _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
        character.video,
      );
      _nativePlaying = true;
    } else {
      final base = _baseVideo;
      if (base == null) return;
      await base.seekTo(Duration.zero);
      _lastObservedVideoPosition = Duration.zero;
      _videoClock.sync(Duration.zero, DateTime.now());
      video = base;
      _activeVideoAsset = character.video;
      _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
        character.video,
      );
      if (!_baseListenerAttached) {
        base.addListener(_handleVideoUpdate);
        _baseListenerAttached = true;
      }
      await base.play();
      _baseCompletionHandled = false;
    }
    renderSignal.value++;
    notifyListeners();
  }

  Future<void> _playRandomEmotion() async {
    if (_disposed ||
        !_videoPlaybackEnabled ||
        character.emotionalVideos.isEmpty) {
      _emotionCycle.emotionFinished();
      return;
    }

    final token = ++_playbackToken;
    final emotionVideo = _selectEmotionVideo();
    _emotionPlaying = true;
    _emotionTransitioning = true;
    _emotionCompletionHandled = false;

    if (usesNativeStage) {
      final channel = _nativeStageChannel;
      if (channel == null) {
        _emotionPlaying = false;
        _emotionTransitioning = false;
        _emotionCycle.emotionFinished();
        await _restartBaseVideo();
        return;
      }
      try {
        await channel.invokeMethod<bool>('playEmotion', <String, Object>{
          'video': emotionVideo,
        });
        if (token != _playbackToken || _disposed) return;
        _activeVideoAsset = emotionVideo;
        _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
          emotionVideo,
        );
        _emotionTransitioning = false;
        notifyListeners();
      } catch (caught) {
        if (token == _playbackToken) {
          statusMessage = 'Emotion video failed: $caught';
          await _returnToBaseVideo(cancelPending: true);
        }
      }
      return;
    }

    VideoPlayerController? emotionController;
    var attached = false;
    try {
      emotionController = VideoPlayerController.asset(
        emotionVideo,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await emotionController.initialize();
      await emotionController.setLooping(false);
      await emotionController.setVolume(0);
      if (token != _playbackToken || _disposed || !_videoPlaybackEnabled) {
        return;
      }

      final base = _baseVideo;
      if (base == null) throw StateError('Base video is unavailable.');
      if (_baseListenerAttached) {
        base.removeListener(_handleVideoUpdate);
        _baseListenerAttached = false;
      }
      await base.pause();

      video = emotionController;
      _activeVideoAsset = emotionVideo;
      _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
        emotionVideo,
      );
      emotionController.addListener(_handleVideoUpdate);
      attached = true;
      renderSignal.value++;
      notifyListeners();
      await emotionController.play();
    } catch (caught) {
      if (token == _playbackToken) {
        statusMessage = 'Emotion video failed: $caught';
        await _returnToBaseVideo(cancelPending: true);
      }
    } finally {
      if (!attached) await emotionController?.dispose();
    }
  }

  String _selectEmotionVideo() {
    final selected = chooseEmotionVideo(
      choices: character.emotionalVideos,
      previous: _lastEmotionVideo,
      random: _random,
    );
    _lastEmotionVideo = selected;
    return selected;
  }

  Future<void> _handleEmotionCompleted() async {
    if (!_emotionPlaying && !_emotionTransitioning) return;
    await _returnToBaseVideo();
  }

  Future<void> _returnToBaseVideo({bool cancelPending = false}) async {
    if (_disposed || _returningToBase) return;
    _returningToBase = true;
    _playbackToken++;
    _emotionCompletionHandled = true;

    try {
      if (usesNativeStage) {
        try {
          await _nativeStageChannel?.invokeMethod<bool>(
            'playBase',
            <String, Object>{'play': _videoPlaybackEnabled},
          );
        } catch (caught) {
          statusMessage = 'Returning to the base video failed: $caught';
        }
        _activeVideoAsset = character.video;
        _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
          character.video,
        );
        _nativePlaying = _videoPlaybackEnabled;
        _baseCompletionHandled = false;
      } else {
        final active = video;
        final base = _baseVideo;
        if (base != null && active != base) {
          active?.removeListener(_handleVideoUpdate);
          video = base;
          if (!_baseListenerAttached) {
            base.addListener(_handleVideoUpdate);
            _baseListenerAttached = true;
          }
          _activeVideoAsset = character.video;
          _activeVideoUsesMouthOverlay = character.usesMouthOverlayFor(
            character.video,
          );
          await active?.dispose();
        }
        if (base != null) {
          if (!_baseListenerAttached) {
            base.addListener(_handleVideoUpdate);
            _baseListenerAttached = true;
          }
          await base.seekTo(Duration.zero);
          _lastObservedVideoPosition = Duration.zero;
          _videoClock.sync(Duration.zero, DateTime.now());
          if (_videoPlaybackEnabled) {
            await base.play();
          } else {
            await base.pause();
          }
          _baseCompletionHandled = false;
        }
      }

      _emotionPlaying = false;
      _emotionTransitioning = false;
      _baseCycleWaitingForSilence = false;
      _emotionCycle.emotionFinished();
      if (cancelPending) _emotionCycle.cancelPending();
      renderSignal.value++;
      notifyListeners();
    } finally {
      _returningToBase = false;
    }
  }

  void _cancelPlaybackState() {
    _playbackToken++;
    _emotionCycle.reset();
    _emotionPlaying = false;
    _emotionTransitioning = false;
    _baseCycleWaitingForSilence = false;
    _emotionCompletionHandled = false;
    _baseCompletionHandled = false;
  }

  void _resetAudio() {
    volume = 0;
    _envelope = 0;
    _noiseFloor = 0.002;
    _levelPeak = 0.02;
    _mouthLevel = 0;
    _smoothedHighRatio = 0;
    _loudSpeechSamples = 0;
    _quietSpeechSamples = 0;
    _analyzer.reset();
    _toneMapper.reset();
    volumeSignal.value = 0;
    _setMouthState(MouthState.closed, force: true);
  }

  Future<void> toggleVideo() async {
    if (usesNativeStage) {
      try {
        final playing = await _nativeStageChannel?.invokeMethod<bool>('toggle');
        if (playing != null) {
          _nativePlaying = playing;
          _videoPlaybackEnabled = playing;
          if (playing && _baseCycleWaitingForSilence) {
            _baseCycleWaitingForSilence = false;
            _baseCompletionHandled = false;
            _emotionCycle.cancelPending();
          }
          if (!playing && (_emotionPlaying || _emotionTransitioning)) {
            await _returnToBaseVideo(cancelPending: true);
          } else {
            _updateEmotionEnabled();
          }
        }
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
      _videoPlaybackEnabled = false;
      _emotionCycle.setEnabled(false);
      if (_emotionPlaying || _emotionTransitioning) {
        await _returnToBaseVideo(cancelPending: true);
        notifyListeners();
        return;
      }
      final position = await controller.position ?? controller.value.position;
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
    } else {
      _videoPlaybackEnabled = true;
      if (_baseCycleWaitingForSilence) {
        _baseCycleWaitingForSilence = false;
        _emotionCycle.cancelPending();
      }
      if (controller.value.isCompleted && controller == _baseVideo) {
        await controller.seekTo(Duration.zero);
        _baseCompletionHandled = false;
      }
      final position = await controller.position ?? controller.value.position;
      _lastObservedVideoPosition = position;
      _videoClock.sync(position, DateTime.now());
      await controller.play();
      _updateEmotionEnabled();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackToken++;
    _emotionCycle.reset();
    _frameTimer?.cancel();
    _nativeStageChannel?.setMethodCallHandler(null);
    renderSignal.dispose();
    volumeSignal.dispose();
    mouthStateSignal.dispose();
    video?.removeListener(_handleVideoUpdate);
    if (_baseVideo != null && _baseVideo != video) {
      _baseVideo?.removeListener(_handleVideoUpdate);
    }
    unawaited(_audioSubscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(video?.dispose());
    if (_baseVideo != null && _baseVideo != video) {
      unawaited(_baseVideo?.dispose());
    }
    for (final image in sprites.values) {
      image.dispose();
    }
    super.dispose();
  }
}
