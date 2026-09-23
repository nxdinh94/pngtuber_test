import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/emotion_cycle.dart';

void main() {
  test('initial silence does not create an emotion request', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.silenceDetected();

    expect(cycle.hasObservedSpeech, isFalse);
    expect(cycle.isEmotionPending, isFalse);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isFalse);
  });

  test('microphone stop preserves pending silent video playback', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.speechStarted();
    cycle.microphoneStopped();

    expect(cycle.isSilent, isTrue);
    expect(cycle.isEmotionPending, isTrue);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isTrue);
  });

  test('speech stopping during a base cycle marks an emotion pending', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.speechStarted();
    cycle.silenceDetected();

    expect(cycle.isSilent, isTrue);
    expect(cycle.isEmotionPending, isTrue);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isTrue);
    expect(cycle.isEmotionPlaying, isTrue);
  });

  test('speech before the base cycle ends cancels the pending emotion', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.speechStarted();
    cycle.silenceDetected();
    cycle.speechStarted();

    expect(cycle.isSilent, isFalse);
    expect(cycle.isEmotionPending, isFalse);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isFalse);
  });

  test(
    'speech during an emotion prevents another emotion from being queued',
    () {
      final cycle = EmotionCycleState()..setEnabled(true);

      cycle.speechStarted();
      cycle.silenceDetected();
      expect(cycle.consumeEmotionAtBaseCycleEnd(), isTrue);
      cycle.speechStarted();
      cycle.silenceDetected();
      cycle.emotionFinished();

      expect(cycle.isEmotionPlaying, isFalse);
      expect(cycle.isEmotionPending, isFalse);
    },
  );

  test(
    'emotion selection does not immediately repeat when alternatives exist',
    () {
      final random = math.Random(7);
      final choices = <String>['cry.mp4', 'laughing.mp4'];

      final first = chooseEmotionVideo(choices: choices, random: random);
      final second = chooseEmotionVideo(
        choices: choices,
        previous: first,
        random: random,
      );

      expect(second, isNot(first));
    },
  );

  test('continued silence schedules the next emotion after the base cycle', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.speechStarted();
    cycle.silenceDetected();
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isTrue);
    cycle.emotionFinished();

    expect(cycle.isEmotionPending, isTrue);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isTrue);
  });

  test('manual disable and reset cancel pending and stale state', () {
    final cycle = EmotionCycleState()..setEnabled(true);

    cycle.speechStarted();
    cycle.silenceDetected();
    cycle.setEnabled(false);
    expect(cycle.consumeEmotionAtBaseCycleEnd(), isFalse);

    cycle.reset();
    expect(cycle.hasObservedSpeech, isFalse);
    expect(cycle.isSilent, isFalse);
    expect(cycle.isEmotionPending, isFalse);
    expect(cycle.isEmotionPlaying, isFalse);
  });
}
