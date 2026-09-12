class VideoPlaybackClock {
  Duration _anchorPosition = Duration.zero;
  DateTime _anchorTime = DateTime.fromMillisecondsSinceEpoch(0);

  void sync(Duration position, DateTime time) {
    _anchorPosition = position;
    _anchorTime = time;
  }

  Duration positionAt({
    required DateTime time,
    required Duration duration,
    required bool playing,
    double speed = 1,
  }) {
    if (!playing || duration <= Duration.zero) return _anchorPosition;
    final elapsedMicroseconds = time.difference(_anchorTime).inMicroseconds;
    final advancedMicroseconds =
        _anchorPosition.inMicroseconds + (elapsedMicroseconds * speed).round();
    return Duration(
      microseconds: advancedMicroseconds % duration.inMicroseconds,
    );
  }
}
