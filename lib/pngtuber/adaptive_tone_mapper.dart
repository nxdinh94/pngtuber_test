class AdaptiveToneMapper {
  double? _low;
  double? _high;

  double normalize(double value) {
    final input = value.clamp(0.0, 1.0);
    if (_low == null || _high == null) {
      _low = input;
      _high = input;
      return 0.5;
    }

    // Remember the speaker's recent spectral range while allowing old
    // extremes to expire slowly as microphone conditions change.
    _low = input < _low! ? input : (_low! + 0.0004).clamp(0.0, input);
    _high = input > _high! ? input : (_high! - 0.0004).clamp(input, 1.0);
    final span = _high! - _low!;
    if (span < 0.012) return 0.5;
    return ((input - _low!) / span).clamp(0.0, 1.0);
  }

  void reset() {
    _low = null;
    _high = null;
  }
}
