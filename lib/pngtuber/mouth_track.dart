import 'dart:convert';
import 'dart:ui';

class MouthTrackCalibration {
  const MouthTrackCalibration({
    required this.offset,
    required this.scale,
    required this.rotation,
  });

  final Offset offset;
  final double scale;
  final double rotation;

  factory MouthTrackCalibration.fromJson(Map<String, dynamic> json) {
    final offset = _numberList(
      json['offset'],
      expectedLength: 2,
      name: 'calibration.offset',
    );
    return MouthTrackCalibration(
      offset: Offset(offset[0], offset[1]),
      scale: _number(json['scale'], 'calibration.scale'),
      rotation: _number(json['rotation'], 'calibration.rotation'),
    );
  }
}

class MouthTrackFrame {
  const MouthTrackFrame({required this.quad, required this.valid});

  final List<Offset> quad;
  final bool valid;

  factory MouthTrackFrame.fromJson(Map<String, dynamic> json) {
    final rawQuad = json['quad'];
    if (rawQuad is! List || rawQuad.length != 4) {
      throw const FormatException('Every frame.quad must contain four points.');
    }
    final quad = rawQuad.indexed
        .map((entry) {
          final values = _numberList(
            entry.$2,
            expectedLength: 2,
            name: 'frame.quad[${entry.$1}]',
          );
          return Offset(values[0], values[1]);
        })
        .toList(growable: false);
    final valid = json['valid'];
    if (valid is! bool) {
      throw const FormatException('Every frame.valid value must be a boolean.');
    }
    return MouthTrackFrame(quad: quad, valid: valid);
  }
}

class MouthTrackData {
  const MouthTrackData({
    required this.fps,
    required this.width,
    required this.height,
    required this.refSpriteSize,
    required this.calibration,
    required this.calibrationApplied,
    required this.frames,
  });

  final double fps;
  final int width;
  final int height;
  final Size refSpriteSize;
  final MouthTrackCalibration calibration;
  final bool calibrationApplied;
  final List<MouthTrackFrame> frames;

  factory MouthTrackData.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'mouth_track.json must contain a JSON object.',
      );
    }
    final fps = _number(decoded['fps'], 'fps');
    final width = _integer(decoded['width'], 'width');
    final height = _integer(decoded['height'], 'height');
    final sprite = _numberList(
      decoded['refSpriteSize'],
      expectedLength: 2,
      name: 'refSpriteSize',
    );
    final rawCalibration = decoded['calibration'];
    final rawFrames = decoded['frames'];
    if (fps <= 0 || width <= 0 || height <= 0) {
      throw const FormatException('fps, width, and height must be positive.');
    }
    if (rawCalibration is! Map<String, dynamic>) {
      throw const FormatException('calibration must be a JSON object.');
    }
    if (rawFrames is! List || rawFrames.isEmpty) {
      throw const FormatException('frames must be a non-empty list.');
    }
    final frames = rawFrames
        .map((frame) {
          if (frame is! Map<String, dynamic>) {
            throw const FormatException('Every frame must be a JSON object.');
          }
          return MouthTrackFrame.fromJson(frame);
        })
        .toList(growable: false);

    return MouthTrackData(
      fps: fps,
      width: width,
      height: height,
      refSpriteSize: Size(sprite[0], sprite[1]),
      calibration: MouthTrackCalibration.fromJson(rawCalibration),
      calibrationApplied: decoded['calibrationApplied'] == true,
      frames: frames,
    );
  }

  MouthTrackFrame frameAt(
    Duration position, {
    bool presentationTimestamp = false,
  }) {
    final frame =
        position.inMicroseconds * fps / Duration.microsecondsPerSecond;
    // Decoder PTS is rounded to microseconds (24 fps frame 1 is 41666 us).
    // Flooring it would select the previous quad on many frame boundaries.
    final index =
        (presentationTimestamp ? frame.round() : frame.floor()) % frames.length;
    return frames[index];
  }
}

double _number(Object? value, String name) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('$name must be a finite number.');
}

int _integer(Object? value, String name) {
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('$name must be an integer.');
}

List<double> _numberList(
  Object? value, {
  required int expectedLength,
  required String name,
}) {
  if (value is! List || value.length != expectedLength) {
    throw FormatException('$name must contain $expectedLength numbers.');
  }
  return value.indexed
      .map((entry) => _number(entry.$2, '$name[${entry.$1}]'))
      .toList(growable: false);
}
