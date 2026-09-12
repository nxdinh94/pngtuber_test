import 'pngtuber_math.dart';

class MouthTransitionGate {
  MouthState? _candidate;
  DateTime _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAccepted = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldAccept({
    required MouthState current,
    required MouthState next,
    required DateTime now,
  }) {
    if (next == current) {
      _candidate = null;
      return false;
    }
    if (_candidate != next) {
      _candidate = next;
      _candidateSince = now;
      return false;
    }

    final stability = switch (next) {
      MouthState.closed => const Duration(milliseconds: 25),
      MouthState.half => const Duration(milliseconds: 35),
      MouthState.open ||
      MouthState.e ||
      MouthState.u => const Duration(milliseconds: 55),
    };
    const minimumHold = Duration(milliseconds: 140);
    if (now.difference(_candidateSince) < stability ||
        now.difference(_lastAccepted) < minimumHold) {
      return false;
    }

    _candidate = null;
    _lastAccepted = now;
    return true;
  }

  void forceAccept(DateTime now) {
    _candidate = null;
    _lastAccepted = now;
  }
}
