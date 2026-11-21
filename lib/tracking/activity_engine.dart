import '../core/geo.dart';
import '../places/place_store.dart';
import 'fix.dart';
import 'motion_engine.dart';
import 'place_monitor.dart';
import 'tuning.dart';

/// What GoliCat should be doing. The animation layer turns changes between
/// these into visible transitions (stash the tea, skid, hop onto the chair…).
enum CatMode { starting, idle, waiting, walking, fast, lost, atWork, atHome, studying, hangingOut, jammed }

class ActivitySnapshot {
  const ActivitySnapshot({
    required this.mode,
    required this.motion,
    required this.now,
    required this.phases,
  });
  final CatMode mode;
  final MotionSnapshot motion;
  final DateTime now;

  /// Arrival state at every saved place.
  final Map<PlaceKind, PlacePhase> phases;
  PlacePhase phase(PlaceKind k) => phases[k] ?? PlacePhase.outside;
  PlacePhase get officePhase => phase(PlaceKind.office);
  PlacePhase get homePhase => phase(PlaceKind.home);

  GeoPoint? get position => motion.position;

  Duration? get sinceUpdate =>
      motion.lastReliableAt == null ? null : now.difference(motion.lastReliableAt!);
}

/// Pure decision logic: fixes + time in, [CatMode] out. No plugins, no UI.
class ActivityEngine {
  ActivityEngine({Place? office, Place? home, Place? education, Place? hangout, this.tuning = const Tuning()})
      : motion = MotionEngine(tuning),
        monitors = {
          PlaceKind.office: PlaceMonitor(office, tuning),
          PlaceKind.home: PlaceMonitor(home, tuning),
          PlaceKind.education: PlaceMonitor(education, tuning),
          PlaceKind.hangout: PlaceMonitor(hangout, tuning),
        };

  final Tuning tuning;
  final MotionEngine motion;
  final Map<PlaceKind, PlaceMonitor> monitors;
  PlaceMonitor monitor(PlaceKind k) => monitors[k]!;
  PlaceMonitor get office => monitor(PlaceKind.office);
  PlaceMonitor get home => monitor(PlaceKind.home);
  PlaceMonitor get education => monitor(PlaceKind.education);
  PlaceMonitor get hangout => monitor(PlaceKind.hangout);

  /// When circles overlap, the first present one wins.
  static const _priority = [PlaceKind.office, PlaceKind.education, PlaceKind.hangout, PlaceKind.home];
  static CatMode modeAt(PlaceKind k) => switch (k) {
        PlaceKind.office => CatMode.atWork,
        PlaceKind.home => CatMode.atHome,
        PlaceKind.education => CatMode.studying,
        PlaceKind.hangout => CatMode.hangingOut,
      };
  DateTime? _startedAt;
  CatMode _mode = CatMode.starting;

  CatMode get mode => _mode;

  void start(DateTime now) {
    motion.reset();
    for (final m in monitors.values) {
      m.reset();
    }
    _startedAt = now;
    _mode = CatMode.starting;
  }

  /// Returns place events ('office:arrived', 'home:left', …) for the trip log.
  List<String> addFix(LocationFix f) {
    final used = motion.addFix(f);
    final events = <String>[];
    final snap = motion.snapshot(f.time);
    if (used || f.accuracy <= tuning.placeAccuracyM) {
      for (final e in monitors.entries) {
        final ev = e.value.addFix(f, snap);
        if (ev != null) events.add('${e.key.label}:$ev');
      }
    }
    return events;
  }

  ActivitySnapshot evaluate(DateTime now) {
    final m = motion.snapshot(now);
    CatMode mode;
    final here = _priority.where((k) => monitor(k).present).firstOrNull;
    if (here != null) {
      // Being at a place beats the ordinary modes, and survives indoor GPS loss.
      mode = modeAt(here);
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
          final still = now.difference(m.stationarySince ?? now);
          if (m.stoppedFromFast) {
            // The bus/rickshaw halted: a short wait is normal, longer is a jam.
            mode = still >= tuning.jamDelay ? CatMode.jammed : CatMode.idle;
          } else {
            mode = still >= tuning.teaDelay ? CatMode.waiting : CatMode.idle;
          }
        case MotionKind.unknown:
          mode = CatMode.starting;
      }
    }
    _mode = mode;
    return ActivitySnapshot(
      mode: mode,
      motion: m,
      now: now,
      phases: {for (final e in monitors.entries) e.key: e.value.phase},
    );
  }

  /// True when the phone may sample less often (still for a while, or settled at a place).
  bool wantsSlowSampling(DateTime now) {
    final m = motion.snapshot(now);
    if (monitors.values.any((p) => p.present)) return m.kind == MotionKind.stationary;
    return m.kind == MotionKind.stationary &&
        m.stationarySince != null &&
        now.difference(m.stationarySince!) >= tuning.slowSamplingAfter;
  }
}
