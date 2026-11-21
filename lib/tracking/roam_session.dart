import 'package:flutter/foundation.dart';

import '../cat/cat_director.dart';
import '../cat/cat_source.dart';
import '../core/position_glide.dart';
import 'activity_engine.dart';
import 'fix.dart';
import 'place_monitor.dart';
import 'trip_recorder.dart';
import 'tuning.dart';

/// Glues one trip together: engine (decisions) → director (animation) and
/// the trip journal. Used identically by real trips and the demo.
class RoamSession extends ChangeNotifier implements CatSource {
  RoamSession({
    required this.clock,
    Place? office,
    Place? home,
    this.tuning = const Tuning(),
    this.demo = false,
    bool reducedMotion = false,
    TripLog? previous,
  })  : engine = ActivityEngine(office: office, home: home, tuning: tuning),
        director = CatDirector(reducedMotion: reducedMotion) {
    log = previous ?? TripLog(startedAt: clock(), demo: demo);
    director.onClipStart = (c) {
      log.addClip(c, clock());
      onJournalChanged?.call();
    };
    engine.start(clock());
    log.addClip(director.clip, clock());
  }

  final DateTime Function() clock;
  final Tuning tuning;
  final bool demo;
  final ActivityEngine engine;
  @override
  final CatDirector director;
  late final TripLog log;
  final _meter = DistanceMeter();
  VoidCallback? onJournalChanged;

  ActivitySnapshot? snap;
  @override
  final position = PositionGlide();

  @override
  bool get moving => snap?.motion.moving ?? false;
  @override
  double get headingDeg => snap?.motion.headingDeg ?? 0;

  void addFix(LocationFix f) {
    engine.addFix(f);
    evaluate();
  }

  void evaluate() {
    final now = clock();
    final s = engine.evaluate(now);
    snap = s;
    log.distanceM += _meter.add(s);
    director.setMode(s.mode);
    director.cadence = s.motion.kind.name == 'fast'
        ? (s.motion.speed / 6).clamp(0.8, 1.4)
        : (s.motion.speed / 1.4).clamp(0.75, 1.6);
    final p = s.position;
    if (p != null) position.target(p, now);
    notifyListeners();
  }

  void setPlace(String which, Place? p) {
    (which == 'office' ? engine.office : engine.home).placeChanged(p);
    evaluate();
  }

  TripLog finish() {
    log.endedAt = clock();
    return log;
  }
}
