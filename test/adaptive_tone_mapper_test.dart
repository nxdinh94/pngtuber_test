import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/adaptive_tone_mapper.dart';

void main() {
  test('centers the first sample and maps the observed microphone range', () {
    final mapper = AdaptiveToneMapper();

    expect(mapper.normalize(0.12), 0.5);
    expect(mapper.normalize(0.22), greaterThan(0.95));
    expect(mapper.normalize(0.12), lessThan(0.05));
    expect(mapper.normalize(0.17), closeTo(0.5, 0.02));
  });

  test('reset discards calibration from the previous stream', () {
    final mapper = AdaptiveToneMapper();
    mapper.normalize(0.1);
    mapper.normalize(0.3);
    mapper.reset();

    expect(mapper.normalize(0.3), 0.5);
  });
}
