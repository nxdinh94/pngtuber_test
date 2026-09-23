import 'dart:math' as math;

/// Selects an emotion uniformly, avoiding an immediate repeat when possible.
String chooseEmotionVideo({
  required List<String> choices,
  required math.Random random,
  String? previous,
}) {
  if (choices.isEmpty) {
    throw ArgumentError('At least one emotion video is required.');
  }
  final available = choices.length > 1 && previous != null
      ? choices.where((path) => path != previous).toList()
      : choices;
  return available[random.nextInt(available.length)];
}

/// Playback state for the cycle-aligned emotional-video behavior.
///
/// This class contains no timers or video APIs. It only decides whether a
/// completed base cycle should start an emotion, which makes the speech and
/// cycle-boundary rules deterministic and easy to test.
class EmotionCycleState {
  bool _enabled = false;
  bool _hasObservedSpeech = false;
  bool _silent = false;
  bool _emotionPlaying = false;
  bool _emotionPending = false;
  bool _speechResumedDuringEmotion = false;

  bool get hasObservedSpeech => _hasObservedSpeech;
  bool get isSilent => _silent;
  bool get isEmotionPlaying => _emotionPlaying;
  bool get isEmotionPending => _emotionPending;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _emotionPending = false;
    }
  }

  void speechStarted() {
    _hasObservedSpeech = true;
    _silent = false;
    _emotionPending = false;
    if (_emotionPlaying) {
      _speechResumedDuringEmotion = true;
    }
  }

  void silenceDetected() {
    _silent = true;
    if (_enabled && _hasObservedSpeech && !_emotionPlaying) {
      _emotionPending = true;
    }
  }

  /// Stops audio observation without discarding speech history. Once speech
  /// has been observed, microphone-off is confirmed silence for video timing.
  void microphoneStopped() {
    _silent = true;
    if (_enabled && _hasObservedSpeech && !_emotionPlaying) {
      _emotionPending = true;
    }
  }

  /// Consumes the pending emotion at the end of a complete base-video cycle.
  bool consumeEmotionAtBaseCycleEnd() {
    if (!_enabled ||
        !_hasObservedSpeech ||
        !_silent ||
        !_emotionPending ||
        _emotionPlaying) {
      return false;
    }
    _emotionPending = false;
    _emotionPlaying = true;
    return true;
  }

  /// Marks the current emotion complete. If silence is still active, the next
  /// complete base cycle is eligible to play another emotion.
  void emotionFinished() {
    _emotionPlaying = false;
    _emotionPending =
        _enabled &&
        _hasObservedSpeech &&
        _silent &&
        !_speechResumedDuringEmotion;
    _speechResumedDuringEmotion = false;
  }

  void cancelPending() {
    _emotionPending = false;
  }

  void reset() {
    _enabled = false;
    _hasObservedSpeech = false;
    _silent = false;
    _emotionPlaying = false;
    _emotionPending = false;
    _speechResumedDuringEmotion = false;
  }
}
