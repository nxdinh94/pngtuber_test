import 'package:flutter_test/flutter_test.dart';
import 'package:me_pngtuber/pngtuber/mouth_transition_gate.dart';
import 'package:me_pngtuber/pngtuber/pngtuber_math.dart';

void main() {
  final start = DateTime.utc(2026);

  test('requires a stable candidate before switching', () {
    final gate = MouthTransitionGate();

    expect(
      gate.shouldAccept(
        current: MouthState.closed,
        next: MouthState.open,
        now: start,
      ),
      isFalse,
    );
    expect(
      gate.shouldAccept(
        current: MouthState.closed,
        next: MouthState.open,
        now: start.add(const Duration(milliseconds: 40)),
      ),
      isFalse,
    );
    expect(
      gate.shouldAccept(
        current: MouthState.closed,
        next: MouthState.open,
        now: start.add(const Duration(milliseconds: 55)),
      ),
      isTrue,
    );
  });

  test('holds an accepted shape long enough to prevent flicker', () {
    final gate = MouthTransitionGate();
    gate.forceAccept(start);

    gate.shouldAccept(
      current: MouthState.open,
      next: MouthState.e,
      now: start.add(const Duration(milliseconds: 10)),
    );
    expect(
      gate.shouldAccept(
        current: MouthState.open,
        next: MouthState.e,
        now: start.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      gate.shouldAccept(
        current: MouthState.open,
        next: MouthState.e,
        now: start.add(const Duration(milliseconds: 150)),
      ),
      isTrue,
    );
  });

  test('a changed candidate restarts the stability window', () {
    final gate = MouthTransitionGate();
    gate.shouldAccept(current: MouthState.open, next: MouthState.e, now: start);
    gate.shouldAccept(
      current: MouthState.open,
      next: MouthState.u,
      now: start.add(const Duration(milliseconds: 40)),
    );

    expect(
      gate.shouldAccept(
        current: MouthState.open,
        next: MouthState.u,
        now: start.add(const Duration(milliseconds: 80)),
      ),
      isFalse,
    );
  });
}
