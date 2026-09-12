import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/pngtuber_math.dart';

void main() {
  test('smoothStep eases mouth transitions without exceeding its bounds', () {
    expect(smoothStep(-1), 0);
    expect(smoothStep(0), 0);
    expect(smoothStep(0.25), closeTo(0.15625, 1e-12));
    expect(smoothStep(0.5), 0.5);
    expect(smoothStep(0.75), closeTo(0.84375, 1e-12));
    expect(smoothStep(1), 1);
    expect(smoothStep(2), 1);
  });

  group('AITuberKit-compatible mouth state selection', () {
    final allStates = MouthState.values.toSet();
    final thresholds = volumeThresholdsHq(50);

    test('keeps silence closed', () {
      expect(
        selectMouthStateHq(
          level: 0,
          highRatio: 0.5,
          thresholds: thresholds,
          currentState: MouthState.closed,
          available: allStates,
        ),
        MouthState.closed,
      );
    });

    test('uses half state between thresholds', () {
      expect(
        selectMouthStateHq(
          level: thresholds.closed + 0.01,
          highRatio: 0.5,
          thresholds: thresholds,
          currentState: MouthState.closed,
          available: allStates,
        ),
        MouthState.half,
      );
    });

    test('selects E and U from high-frequency ratio', () {
      MouthState select(double ratio) => selectMouthStateHq(
        level: 1,
        highRatio: ratio,
        thresholds: thresholds,
        currentState: MouthState.open,
        available: allStates,
      );
      expect(select(0.8), MouthState.e);
      expect(select(0.2), MouthState.u);
    });
  });

  test('calibration scales, rotates, and offsets around quad center', () {
    final result = applyCalibration(
      const [Offset(0, 0), Offset(10, 0), Offset(10, 4), Offset(0, 4)],
      enabled: true,
      offset: const Offset(3, -2),
      scale: 2,
      rotationDegrees: 90,
    );
    expect(result[0].dx, closeTo(12, 1e-8));
    expect(result[0].dy, closeTo(-10, 1e-8));
  });

  test('affine transform maps all source triangle points', () {
    const s0 = Offset(0, 0);
    const s1 = Offset(2, 0);
    const s2 = Offset(0, 4);
    const d0 = Offset(5, 7);
    const d1 = Offset(9, 7);
    const d2 = Offset(5, 19);
    final transform = computeAffine(s0, s1, s2, d0, d1, d2)!;

    Offset map(Offset point) => Offset(
      transform.a * point.dx + transform.c * point.dy + transform.e,
      transform.b * point.dx + transform.d * point.dy + transform.f,
    );

    expect(map(s0), d0);
    expect(map(s1), d1);
    expect(map(s2), d2);
  });
}
