import 'dart:math' as math;
import 'dart:ui';

enum MouthState { closed, half, open, e, u }

double smoothStep(double progress) {
  final value = progress.clamp(0.0, 1.0);
  return value * value * (3 - 2 * value);
}

class VolumeThresholds {
  const VolumeThresholds({required this.closed, required this.half});

  final double closed;
  final double half;
}

VolumeThresholds volumeThresholdsHq(double sensitivity) {
  final s = sensitivity.clamp(0, 100) / 100;
  return VolumeThresholds(
    closed: 0.07 + (1 - s) * 0.08,
    half: 0.22 + (1 - s) * 0.12,
  );
}

MouthState selectMouthStateHq({
  required double level,
  required double highRatio,
  required VolumeThresholds thresholds,
  required MouthState currentState,
  required Set<MouthState> available,
}) {
  final hasHalf = available.contains(MouthState.half);
  var state = switch (currentState) {
    MouthState.e || MouthState.u => MouthState.open,
    _ => currentState,
  };
  final closeThreshold = math.max(0.02, thresholds.closed - 0.03);
  final halfDownThreshold = math.max(
    closeThreshold + 0.02,
    thresholds.half - 0.02,
  );

  switch (state) {
    case MouthState.closed:
      if (level >= thresholds.half) {
        state = MouthState.open;
      } else if (level >= thresholds.closed) {
        state = hasHalf ? MouthState.half : MouthState.open;
      }
    case MouthState.half:
      if (level < closeThreshold) {
        state = MouthState.closed;
      } else if (level >= thresholds.half) {
        state = MouthState.open;
      }
    case MouthState.open:
      if (level < closeThreshold) {
        state = MouthState.closed;
      } else if (level < halfDownThreshold && hasHalf) {
        state = MouthState.half;
      }
    case MouthState.e || MouthState.u:
      throw StateError(
        'Vowel states are normalized before transition handling.',
      );
  }

  if (state == MouthState.open) {
    if (highRatio > 0.62 && available.contains(MouthState.e)) {
      return MouthState.e;
    }
    if (highRatio < 0.38 && available.contains(MouthState.u)) {
      return MouthState.u;
    }
  }
  return state;
}

List<Offset> applyCalibration(
  List<Offset> quad, {
  required bool enabled,
  required Offset offset,
  required double scale,
  required double rotationDegrees,
}) {
  if (!enabled) return List<Offset>.of(quad, growable: false);
  final center = quad.reduce((a, b) => a + b) / quad.length.toDouble();
  final angle = rotationDegrees * math.pi / 180;
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return quad
      .map((point) {
        final local = (point - center) * scale;
        return Offset(
          local.dx * cosine - local.dy * sine + center.dx + offset.dx,
          local.dx * sine + local.dy * cosine + center.dy + offset.dy,
        );
      })
      .toList(growable: false);
}

class AffineTransform {
  const AffineTransform(this.a, this.b, this.c, this.d, this.e, this.f);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;
}

AffineTransform? computeAffine(
  Offset s0,
  Offset s1,
  Offset s2,
  Offset d0,
  Offset d1,
  Offset d2,
) {
  final denominator =
      s0.dx * (s1.dy - s2.dy) +
      s1.dx * (s2.dy - s0.dy) +
      s2.dx * (s0.dy - s1.dy);
  if (denominator.abs() < 1e-9) return null;

  return AffineTransform(
    (d0.dx * (s1.dy - s2.dy) +
            d1.dx * (s2.dy - s0.dy) +
            d2.dx * (s0.dy - s1.dy)) /
        denominator,
    (d0.dy * (s1.dy - s2.dy) +
            d1.dy * (s2.dy - s0.dy) +
            d2.dy * (s0.dy - s1.dy)) /
        denominator,
    (d0.dx * (s2.dx - s1.dx) +
            d1.dx * (s0.dx - s2.dx) +
            d2.dx * (s1.dx - s0.dx)) /
        denominator,
    (d0.dy * (s2.dx - s1.dx) +
            d1.dy * (s0.dx - s2.dx) +
            d2.dy * (s1.dx - s0.dx)) /
        denominator,
    (d0.dx * (s1.dx * s2.dy - s2.dx * s1.dy) +
            d1.dx * (s2.dx * s0.dy - s0.dx * s2.dy) +
            d2.dx * (s0.dx * s1.dy - s1.dx * s0.dy)) /
        denominator,
    (d0.dy * (s1.dx * s2.dy - s2.dx * s1.dy) +
            d1.dy * (s2.dx * s0.dy - s0.dx * s2.dy) +
            d2.dy * (s0.dx * s1.dy - s1.dx * s0.dy)) /
        denominator,
  );
}
