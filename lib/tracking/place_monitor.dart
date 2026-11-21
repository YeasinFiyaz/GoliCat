import 'dart:math' as math;

import '../core/geo.dart';
import 'fix.dart';
import 'motion_engine.dart';
import 'tuning.dart';

/// A saved place such as the office or home.
class Place {
  const Place({required this.center, required this.radiusM});
  final GeoPoint center;
  final double radiusM;

  double get exitRadiusM => Tuning.exitRadiusFor(radiusM);

  Map<String, dynamic> toJson() => {'c': center.toJson(), 'r': radiusM};
  static Place fromJson(Map<String, dynamic> j) => Place(
      center: GeoPoint.fromJson(Map<String, dynamic>.from(j['c'] as Map)),
      radiusM: (j['r'] as num).toDouble());

  Place copyWith({GeoPoint? center, double? radiusM}) =>
      Place(center: center ?? this.center, radiusM: radiusM ?? this.radiusM);
}

enum PlacePhase { outside, dwelling, present }

/// Decides arrival at / departure from one place with hysteresis:
///  * arrival = inside the circle for [Tuning.placeDwell] AND not just passing
///    (little net movement over the last minute, not travelling fast);
///  * departure = reliably beyond the wider exit ring for a while.
/// Poor-accuracy fixes are ignored, so indoor GPS drift can't flip-flop it.
class PlaceMonitor {
  PlaceMonitor(this.place, [this.t = const Tuning()]);

  Place? place;
  final Tuning t;

  PlacePhase _phase = PlacePhase.outside;
  DateTime? _insideSince;
  DateTime? _outsideSince;
  DateTime? _beyondExitSince;
  DateTime? arrivedAt;
  final List<LocationFix> _history = [];

  PlacePhase get phase => _phase;
  bool get present => _phase == PlacePhase.present;
  DateTime? get insideSince => _insideSince;

  void reset() {
    _phase = PlacePhase.outside;
    _insideSince = _outsideSince = _beyondExitSince = arrivedAt = null;
    _history.clear();
  }

  /// Returns 'arrived' / 'left' when the phase changes to/from present.
  String? addFix(LocationFix f, MotionSnapshot motion) {
    final p = place;
    if (p == null) {
      if (_phase != PlacePhase.outside) {
        final was = _phase;
        reset();
        return was == PlacePhase.present ? 'left' : null;
      }
      return null;
    }
    if (f.accuracy > t.placeAccuracyM) return null;
    _history.add(f);
    _history.removeWhere(
        (h) => f.time.difference(h.time) > t.placePassWindow + const Duration(seconds: 5));

    final d = distanceM(p.center, f.point);
    final exitR = p.exitRadiusM;

    switch (_phase) {
      case PlacePhase.outside:
        if (d <= p.radiusM) {
          _phase = PlacePhase.dwelling;
          _insideSince = f.time;
          _outsideSince = null;
        }
      case PlacePhase.dwelling:
        if (d > exitR) {
          _toOutside();
          return null;
        }
        if (d > p.radiusM) {
          _outsideSince ??= f.time;
          if (f.time.difference(_outsideSince!) > t.placeOutsideGrace) {
            _toOutside();
            return null;
          }
        } else {
          _outsideSince = null;
        }
        if (f.time.difference(_insideSince!) >= t.placeDwell &&
            d <= p.radiusM &&
            motion.kind != MotionKind.fast &&
            _netMovement(f.time) <= t.placePassMaxNetM) {
          _phase = PlacePhase.present;
          arrivedAt = f.time;
          _beyondExitSince = null;
          return 'arrived';
        }
      case PlacePhase.present:
        if (d > exitR) {
          _beyondExitSince ??= f.time;
          final farAndMoving = motion.moving && d > exitR + 25;
          if (farAndMoving ||
              f.time.difference(_beyondExitSince!) >= t.placeExitConfirm) {
            _toOutside();
            return 'left';
          }
        } else {
          _beyondExitSince = null;
        }
    }
    return null;
  }

  void _toOutside() {
    _phase = PlacePhase.outside;
    _insideSince = _outsideSince = _beyondExitSince = arrivedAt = null;
  }

  /// Net displacement across the pass window (straight-line walk-by is large).
  double _netMovement(DateTime now) {
    final w = _history
        .where((h) => now.difference(h.time) <= t.placePassWindow)
        .toList();
    if (w.length < 3) return 0;
    // Compare the average position of the first and last thirds: a straight
    // walk-by shows up clearly, indoor jitter averages out.
    final n = math.max(1, w.length ~/ 3);
    return distanceM(_mean(w.sublist(0, n)), _mean(w.sublist(w.length - n)));
  }

  static GeoPoint _mean(List<LocationFix> fs) {
    double lat = 0, lng = 0;
    for (final f in fs) {
      lat += f.point.lat;
      lng += f.point.lng;
    }
    return GeoPoint(lat / fs.length, lng / fs.length);
  }

  /// Force a state (used when a place is moved/resized mid-trip).
  void placeChanged(Place? newPlace) {
    final wasPresent = present;
    place = newPlace;
    if (newPlace == null) {
      reset();
    } else if (!wasPresent) {
      _phase = PlacePhase.outside;
      _insideSince = _outsideSince = null;
    }
  }
}
