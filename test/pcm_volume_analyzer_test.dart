import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/pcm_volume_analyzer.dart';

void main() {
  test('analyzes PCM16 input and can be reset between streams', () {
    final analyzer = PcmVolumeAnalyzer(sampleRate: 600);
    final bytes = ByteData(20);
    for (var index = 0; index < 10; index++) {
      bytes.setInt16(index * 2, index.isEven ? 12000 : -12000, Endian.little);
    }

    final first = analyzer.add(bytes.buffer.asUint8List()).single;
    expect(first.rms, greaterThan(0.3));
    expect(first.high, greaterThan(0));

    analyzer.reset();
    final second = analyzer.add(bytes.buffer.asUint8List()).single;
    expect(second.rms, closeTo(first.rms, 1e-12));
    expect(second.low, closeTo(first.low, 1e-12));
    expect(second.high, closeTo(first.high, 1e-12));
  });

  test('preserves an odd trailing byte for the next chunk', () {
    final analyzer = PcmVolumeAnalyzer(sampleRate: 60);
    expect(analyzer.add(Uint8List.fromList([0x00])), isEmpty);
    final samples = analyzer.add(Uint8List.fromList([0x40]));
    expect(samples, hasLength(1));
    expect(samples.single.rms, closeTo(0.5, 1e-12));
  });
}
