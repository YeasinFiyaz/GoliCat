import '../core/geo.dart';
import 'fix.dart';
import 'motion_engine.dart';
import 'place_monitor.dart';
import 'tuning.dart';

/// What GoliCat should be doing. The animation layer turns changes between
/// these into visible transitions (stash the tea, skid, hop onto the chair…).
enum CatMode { starting, idle, waiting, walking, fast, lost, atWork, atHome }

class ActivitySnapshot {
  const ActivitySnapshot({
    required this.mode,
    required this.motion,
    required this.now,
    required this.officePhase,
    required this.homePhase,
  });
  final CatMode mode;
  final MotionSnapshot motion;
  final DateTime now;
  final PlacePhase officePhase;
  final PlacePhase homePhase;

  GeoPoint? get position => motion.position;

  Duration? get sinceUpdate =>
      motion.lastReliableAt == null ? null : now.difference(motion.lastReliableAt!);
}

/// Pure decision logic: fixes + time in, [CatMode] out. No plugins, no UI.
class ActivityEngine {
  ActivityEngine({Place? office, Place? home, this.tuning = const Tuning()})
      : motion = MotionEngine(tuning),
        office = PlaceMonitor(office, tuning),
        home = PlaceMonitor(home, tuning);

  final Tuning tuning;
  final MotionEngine motion;
  final PlaceMonitor office;
  final PlaceMonitor home;
  DateTime? _startedAt;
  CatMode _mode = CatMode.starting;

  CatMode get mode => _mode;

  void start(DateTime now) {
    motion.reset();
    office.reset();
    home.reset();
    _startedAt = now;
    _mode = CatMode.starting;
  }

  /// Returns place events ('office:arrived', 'home:left', …) for the trip log.
  List<String> addFix(LocationFix f) {
    final used = motion.addFix(f);
    final events = <String>[];
    final snap = motion.snapshot(f.time);
    if (used || f.accuracy <= tuning.placeAccuracyM) {
      final o = office.addFix(f, snap);
      if (o != null) events.add('office:$o');
      final h = home.addFix(f, snap);
      if (h != null) events.add('home:$h');
    }
    return events;
  }

  ActivitySnapshot evaluate(DateTime now) {
    final m = motion.snapshot(now);
    CatMode mode;
    if (office.present) {
      // Office typing beats the ordinary tea break, and survives indoor GPS loss.
      mode = CatMode.atWork;
    } else if (home.present) {
      mode = CatMode.atHome;
    } else if (m.position == null) {
      final waited = _startedAt == null ? Duration.zero : now.difference(_startedAt!);
      mode = waited > tuning.staleAfter ? CatMode.lost : CatMode.starting;
    } else if (m.stale) {
      mode = CatMode.lost;
    } else {
      switch (m.kind) {
        case MotionKind.walking:
          mode = CatMode.walking;
        case MotionKind.fast:
          mode = CatMode.fast;
        case MotionKind.stationary:
          final since = m.stationarySince ?? now;
          mode = now.difference(since) >= tuning.teaDelay ? CatMode.waiting : CatMode.idle;
        case MotionKind.unknown:
          mode = CatMode.starting;
      }
    }
    _mode = mode;
    return ActivitySnapshot(
      mode: mode,
      motion: m,
      now: now,
      officePhase: office.phase,
      homePhase: home.phase,
    );
  }

  /// True when the phone may sample less often (still for a while, or settled at a place).
  bool wantsSlowSampling(DateTime now) {
    final m = motion.snapshot(now);
    if (office.present || home.present) return m.kind == MotionKind.stationary;
    return m.kind == MotionKind.stationary &&
        m.stationarySince != null &&
        now.difference(m.stationarySince!) >= tuning.slowSamplingAfter;
  }
}
