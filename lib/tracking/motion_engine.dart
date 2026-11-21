import 'dart:math' as math;

import '../core/geo.dart';
import 'fix.dart';
import 'tuning.dart';

enum MotionKind { unknown, stationary, walking, fast }

/// What the motion engine believes right now.
class MotionSnapshot {
  const MotionSnapshot({
    required this.kind,
    required this.position,
    required this.headingDeg,
    required this.speed,
    required this.stationarySince,
    required this.lastReliableAt,
    required this.lastFixAt,
    required this.lastAccuracy,
    required this.stale,
    this.stoppedFromFast = false,
  });

  final MotionKind kind;

  /// Where the cat should stand: the averaged rest point while still,
  /// the smoothed track while moving. Null until the first reliable fix.
  final GeoPoint? position;
  final double headingDeg;
  final double speed;
  final DateTime? stationarySince;
  final DateTime? lastReliableAt;
  final DateTime? lastFixAt;
  final double lastAccuracy;
  final bool stale;

  /// This stop came straight after a ride (vehicle halted, not a walk ending).
  final bool stoppedFromFast;

  bool get moving => kind == MotionKind.walking || kind == MotionKind.fast;
}

/// Turns raw, noisy fixes into stationary / walking / fast decisions.
///
/// Rules that keep a sitting cat sitting:
///  * fixes worse than [Tuning.reliableAccuracyM] are ignored for movement;
///  * physically impossible jumps are dropped;
///  * starting to move needs several consecutive fixes outside the rest
///    circle, each consistent with the last, over at least a couple of seconds.
class MotionEngine {
  MotionEngine([this.t = const Tuning()]);

  final Tuning t;

  MotionKind _kind = MotionKind.unknown;
  GeoPoint? _anchor;
  double _anchorWeight = 0;
  double _anchorAcc = 0;
  DateTime? _stationarySince;

  final List<LocationFix> _candidates = [];
  final List<LocationFix> _recent = [];
  GeoPoint? _smoothed;
  double _speed = 0;
  double _heading = 90;
  int _fastVotes = 0;
  int _slowVotes = 0;
  bool _stoppedFromFast = false;
  DateTime? _lastFastAt;
  LocationFix? _lastReliable;
  DateTime? _lastFixAt;
  DateTime? _firstFixAt;
  DateTime? _lastGoodAt;
  double _lastAcc = 9999;
  bool slowSampling = false;

  MotionKind get kind => _kind;

  void reset() {
    _kind = MotionKind.unknown;
    _anchor = null;
    _anchorWeight = 0;
    _stationarySince = null;
    _candidates.clear();
    _recent.clear();
    _smoothed = null;
    _speed = 0;
    _fastVotes = _slowVotes = 0;
    _stoppedFromFast = false;
    _lastFastAt = null;
    _lastReliable = null;
    _lastFixAt = null;
    _firstFixAt = null;
    _lastGoodAt = null;
    _lastAcc = 9999;
  }

  bool isReliable(LocationFix f) => f.accuracy <= t.reliableAccuracyM;

  /// A coarser fix still counts once good ones have dried up for a while.
  bool _usable(LocationFix f) {
    if (isReliable(f)) return true;
    if (f.accuracy > t.degradedAccuracyM) return false;
    // Measured from the last *good* fix, so once degraded we stay degraded
    // until a good one returns (not: one coarse fix every staleAfter).
    final last = _lastGoodAt ?? _firstFixAt;
    return last == null || f.time.difference(last) > t.staleAfter;
  }

  /// Feed one fix. Returns true if it was used for movement.
  bool addFix(LocationFix f) {
    _lastFixAt = f.time;
    _firstFixAt ??= f.time;
    _lastAcc = f.accuracy;
    if (isReliable(f)) _lastGoodAt = f.time;
    if (!_usable(f)) return false;

    final prev = _lastReliable;
    if (prev != null) {
      final dt = f.time.difference(prev.time).inMilliseconds / 1000.0;
      if (dt <= 0) return false;
      final d = distanceM(prev.point, f.point);
      // Teleport check (allow for the two accuracy circles).
      if ((d - prev.accuracy - f.accuracy) / dt > t.maxPlausibleSpeed) {
        return false;
      }
    }
    _lastReliable = f;
    _recent.add(f);
    _recent.removeWhere(
        (r) => f.time.difference(r.time) > const Duration(seconds: 40));

    switch (_kind) {
      case MotionKind.unknown:
        _becomeStationary(f.point, f.accuracy, f.time);
      case MotionKind.stationary:
        _whileStationary(f);
      case MotionKind.walking:
      case MotionKind.fast:
        _whileMoving(f);
    }
    return true;
  }

  void _becomeStationary(GeoPoint p, double acc, DateTime since) {
    _stoppedFromFast = _lastFastAt != null && since.difference(_lastFastAt!) <= t.jamRecentRide;
    _kind = MotionKind.stationary;
    _anchor = p;
    _anchorWeight = 1 / (acc * acc);
    _anchorAcc = acc;
    _stationarySince = since;
    _candidates.clear();
    _speed = 0;
    _fastVotes = _slowVotes = 0;
  }

  double _restRadius(LocationFix f) =>
      math.max(t.moveRadiusMinM, f.accuracy * 0.8 + _anchorAcc * 0.5);

  void _whileStationary(LocationFix f) {
    final anchor = _anchor!;
    final d = distanceM(anchor, f.point);
    final radius = _restRadius(f);
    // A trustworthy Doppler speed lets a real start show up a little sooner.
    final speedSaysMoving = f.speed >= 0.9 &&
        (f.speedAccuracy < 0 || f.speedAccuracy <= 1.0) &&
        d > math.max(6, f.accuracy * 0.6);
    if (d > radius || speedSaysMoving) {
      if (_candidates.isNotEmpty) {
        final last = _candidates.last;
        final dt = f.time.difference(last.time).inMilliseconds / 1000.0;
        final step = distanceM(last.point, f.point);
        final dLast = distanceM(anchor, last.point);
        // Consistent = not jumping around and not falling back toward the rest point.
        final consistent = step <= 8 * dt + last.accuracy + f.accuracy &&
            d >= dLast - math.max(4, f.accuracy * 0.5);
        if (!consistent) _candidates.clear();
      }
      _candidates.add(f);
      final span = _candidates.last.time.difference(_candidates.first.time);
      if (_candidates.length >= t.moveConfirmFixes && span >= t.moveConfirmSpan) {
        _startMoving();
      }
    } else {
      _candidates.clear();
      // Only fixes close to the rest point refine it; edge fixes might be a start.
      if (d > radius * 0.6) return;
      // Accuracy-weighted running mean keeps the rest point steady.
      final w = 1 / (f.accuracy * f.accuracy);
      final total = _anchorWeight + w;
      _anchor = GeoPoint(
        (anchor.lat * _anchorWeight + f.point.lat * w) / total,
        (anchor.lng * _anchorWeight + f.point.lng * w) / total,
      );
      _anchorWeight = math.min(total, 1 / 9.0); // cap so the mean can follow a slow shuffle
      _anchorAcc = math.min(_anchorAcc, f.accuracy);
    }
  }

  void _startMoving() {
    final first = _candidates.first, last = _candidates.last;
    final dt = last.time.difference(first.time).inMilliseconds / 1000.0;
    final span = distanceM(_anchor!, last.point);
    final firstDt = math.max(1.0, dt);
    _speed = math.max(distanceM(first.point, last.point) / firstDt, span / (firstDt + 1));
    _heading = bearingDeg(_anchor!, last.point);
    _smoothed = last.point;
    _kind = _speed > t.fastSpeed ? MotionKind.fast : MotionKind.walking;
    _stationarySince = null;
    _stoppedFromFast = false;
    _candidates.clear();
    _fastVotes = _slowVotes = 0;
  }

  void _whileMoving(LocationFix f) {
    if (_kind == MotionKind.fast) _lastFastAt = f.time;
    // Position smoothing: trust good fixes more.
    final prev = _smoothed ?? f.point;
    final alpha = (12 / (12 + f.accuracy)).clamp(0.35, 0.85);
    final next = lerpGeo(prev, f.point, alpha);
    if (distanceM(prev, next) > 1.5) _heading = bearingDeg(prev, next);
    if (f.heading >= 0 && f.speed > 1.5) _heading = f.heading;
    _smoothed = next;

    // Speed: reported Doppler speed when trustworthy, otherwise displacement.
    double est;
    if (f.speed >= 0 && (f.speedAccuracy < 0 || f.speedAccuracy <= 1.5)) {
      est = f.speed;
    } else {
      est = _displacementSpeed(f.time, const Duration(seconds: 6)) ?? _speed;
    }
    _speed = _speed * 0.6 + est * 0.4;

    if (_kind == MotionKind.walking) {
      _fastVotes = _speed > t.fastSpeed ? _fastVotes + 1 : 0;
      if (_fastVotes >= 2) {
        _kind = MotionKind.fast;
        _slowVotes = 0;
      }
    } else {
      _slowVotes = _speed < t.fastExitSpeed ? _slowVotes + 1 : 0;
      if (_slowVotes >= 2) {
        _kind = MotionKind.walking;
        _fastVotes = 0;
      }
    }

    // Stop: every recent fix huddles together and we're barely moving.
    final window = _recent
        .where((r) => f.time.difference(r.time) <= t.stopWindow)
        .toList();
    if (window.length >= 4 &&
        f.time.difference(window.first.time) >=
            t.stopWindow - const Duration(seconds: 3)) {
      final c = _centroid(window);
      final spread = window.map((r) => distanceM(c, r.point)).reduce(math.max);
      final meanAcc =
          window.map((r) => r.accuracy).reduce((a, b) => a + b) / window.length;
      final dispSpeed = _displacementSpeed(f.time, t.stopWindow) ?? _speed;
      if (spread <= math.max(t.stopSpreadM, meanAcc * 0.9) &&
          math.min(_speed, dispSpeed) < t.stopSpeed) {
        _becomeStationary(c, meanAcc, window.first.time);
      }
    }
  }

  double? _displacementSpeed(DateTime now, Duration window) {
    final w = _recent.where((r) => now.difference(r.time) <= window).toList();
    if (w.length < 2) return null;
    final dt = w.last.time.difference(w.first.time).inMilliseconds / 1000.0;
    if (dt < 2) return null;
    return distanceM(w.first.point, w.last.point) / dt;
  }

  static GeoPoint _centroid(List<LocationFix> fs) {
    double lat = 0, lng = 0;
    for (final f in fs) {
      lat += f.point.lat;
      lng += f.point.lng;
    }
    return GeoPoint(lat / fs.length, lng / fs.length);
  }

  /// Snapshot at wall/sim time [now] (used for staleness).
  MotionSnapshot snapshot(DateTime now) {
    final lastAt = _lastReliable?.time;
    final staleLimit = slowSampling ? t.staleAfterSlowSampling : t.staleAfter;
    final stale = lastAt == null
        ? (_lastFixAt != null && now.difference(_lastFixAt!) > t.staleAfter)
        : now.difference(lastAt) > staleLimit;
    return MotionSnapshot(
      kind: _kind,
      position: _kind == MotionKind.stationary ? _anchor : (_smoothed ?? _anchor),
      headingDeg: _heading,
      speed: _kind == MotionKind.stationary ? 0 : _speed,
      stationarySince: _stationarySince,
      lastReliableAt: lastAt,
      lastFixAt: _lastFixAt,
      lastAccuracy: _lastAcc,
      stale: stale,
      stoppedFromFast: _kind == MotionKind.stationary && _stoppedFromFast,
    );
  }
}
