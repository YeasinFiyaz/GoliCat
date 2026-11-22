import 'geo.dart';

/// Glides the drawn cat between reliable positions instead of jumping.
class PositionGlide {
  GeoPoint? _from, _to, _shown;
  double _t = 1, _dur = 1;
  DateTime? _lastAt;

  GeoPoint? get shown => _shown;

  /// True while the drawn position is still sliding to the latest fix.
  bool get gliding => _to != null && _t < 1;

  void target(GeoPoint p, DateTime at) {
    if (_to == p) return;
    if (_shown == null) {
      _shown = _from = _to = p;
      _lastAt = at;
      return;
    }
    final gap = _lastAt == null ? 1.0 : at.difference(_lastAt!).inMilliseconds / 1000.0;
    _lastAt = at;
    _from = _shown;
    _to = p;
    _t = 0;
    _dur = gap.clamp(0.4, 1.6);
    // A long jump (e.g. after signal loss) is crossed briskly, not crawled.
    if (distanceM(_from!, p) > 150) _dur = 0.6;
  }

  /// [dt] in seconds of simulated time.
  void advance(double dt) {
    if (_to == null || _t >= 1) return;
    _t = (_t + dt / _dur).clamp(0.0, 1.0);
    _shown = lerpGeo(_from!, _to!, _t);
  }

  void reset() {
    _from = _to = _shown = null;
    _t = 1;
  }
}
