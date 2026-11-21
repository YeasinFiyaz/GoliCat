import '../cat/cat_director.dart';
import '../cat/cat_source.dart';
import '../core/geo.dart';
import '../core/position_glide.dart';
import 'activity_engine.dart';
import 'trip_runner.dart';

/// Drives the on-screen cat from the trip's status reports, the same way the
/// web viewer drives it from a share. The real session lives in the service.
class TripMirror implements CatSource {
  TripMirror({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  final director = CatDirector();
  @override
  final position = PositionGlide();

  TripStatus? status;
  bool _first = true;

  @override
  bool get moving => status?.moving ?? false;
  @override
  double get headingDeg => status?.headingDeg ?? 0;

  GeoPoint? get point => status?.lat == null ? null : GeoPoint(status!.lat!, status!.lng!);

  void apply(TripStatus s) {
    status = s;
    if (_first) {
      director.snapTo(s.mode);
      _first = false;
    } else {
      director.setMode(s.mode);
    }
    director.cadence = s.mode == CatMode.fast ? (s.speed / 6).clamp(0.8, 1.4) : (s.speed / 1.4).clamp(0.75, 1.6);
    final p = point;
    if (p != null) position.target(p, _clock());
  }

  void reset() {
    status = null;
    _first = true;
  }
}
