import 'dart:math' as math;
import 'dart:typed_data';

class VolumeSample {
  const VolumeSample({
    required this.rms,
    required this.low,
    required this.high,
  });

  final double rms;
  final double low;
  final double high;
}

class PcmVolumeAnalyzer {
  PcmVolumeAnalyzer({this.sampleRate = 48000})
    : _reportSamples = math.max(1, sampleRate ~/ 60),
      _lowAlpha = 1 - math.exp((-2 * math.pi * 700) / sampleRate);

  final int sampleRate;
  final int _reportSamples;
  final double _lowAlpha;

  double _lowState = 0;
  double _rmsSum = 0;
  double _lowEnergy = 0;
  double _highEnergy = 0;
  int _sampleCount = 0;
  int? _pendingByte;

  void reset() {
    _lowState = 0;
    _rmsSum = 0;
    _lowEnergy = 0;
    _highEnergy = 0;
    _sampleCount = 0;
    _pendingByte = null;
  }

  List<VolumeSample> add(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    var bytes = chunk;
    if (_pendingByte != null) {
      final joined = Uint8List(chunk.length + 1)..[0] = _pendingByte!;
      joined.setRange(1, joined.length, chunk);
      bytes = joined;
      _pendingByte = null;
    }
    if (bytes.length.isOdd) {
      _pendingByte = bytes.last;
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }

    final output = <VolumeSample>[];
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset < bytes.length; offset += 2) {
      final value = data.getInt16(offset, Endian.little) / 32768.0;
      final low = _lowState + _lowAlpha * (value - _lowState);
      _lowState = low;
      final high = value - low;
      _rmsSum += value * value;
      _lowEnergy += low * low;
      _highEnergy += high * high;
      _sampleCount++;
      if (_sampleCount >= _reportSamples) {
        output.add(
          VolumeSample(
            rms: math.sqrt(_rmsSum / _sampleCount),
            low: _lowEnergy / _sampleCount,
            high: _highEnergy / _sampleCount,
          ),
        );
        _rmsSum = 0;
        _lowEnergy = 0;
        _highEnergy = 0;
        _sampleCount = 0;
      }
    }
    return output;
  }
}
