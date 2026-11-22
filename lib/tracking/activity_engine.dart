import '../core/geo.dart';
import '../places/custom_place.dart';
import '../places/place_store.dart';
import 'fix.dart';
import 'motion_engine.dart';
import 'place_monitor.dart';
import 'tuning.dart';

/// What GoliCat should be doing. The animation layer turns changes between
/// these into visible transitions (stash the tea, skid, hop onto the chair…).
/// Names travel to share viewers: only ever add, never rename.
enum CatMode {
  starting, idle, waiting, walking, fast, lost, atWork, atHome, studying, hangingOut, jammed,
  // At a pin from "More places".
  atBazar, eatingOut, atBusStop, atPark,
}

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
  ActivityEngine({
    Place? office,
    Place? home,
    Place? education,
    Place? hangout,
    List<CustomPlace> custom = const [],
    this.tuning = const Tuning(),
  })
      : motion = MotionEngine(tuning),
        monitors = {
          PlaceKind.office: PlaceMonitor(office, tuning),
          PlaceKind.home: PlaceMonitor(home, tuning),
          PlaceKind.education: PlaceMonitor(education, tuning),
          PlaceKind.hangout: PlaceMonitor(hangout, tuning),
        } {
    setCustomPlaces(custom);
  }

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
  /// Pins from "More places" that have an activity, by pin id.
  final Map<String, PlaceMonitor> customMonitors = {};
  final Map<String, CatMode> _customModes = {};

  /// Circle size for a pin (the user doesn't set one).
  static const customRadiusM = 75.0;

  /// What the cat does at a pin with this icon; null = nothing special
  /// (prayer places, and pins whose scene isn't made yet).
  static CatMode? modeForIcon(String icon) => switch (icon) {
        'home' => CatMode.atHome,
        'work' => CatMode.atWork,
        'school' => CatMode.studying,
        'tea' => CatMode.waiting,
        'friends' || 'family' => CatMode.hangingOut,
        'bazar' => CatMode.atBazar,
        'food' => CatMode.eatingOut,
        'bus' => CatMode.atBusStop,
        'park' => CatMode.atPark,
        _ => null,
      };

  /// Adds, moves or drops pin watchers; an unchanged pin keeps its state.
  void setCustomPlaces(List<CustomPlace> list) {
    final keep = <String>{};
    for (final c in list) {
      final m = modeForIcon(c.icon);
      if (m == null) continue;
      keep.add(c.id);
      _customModes[c.id] = m;
      final place = Place(center: c.center, radiusM: customRadiusM);
      final mon = customMonitors[c.id];
      if (mon == null) {
        customMonitors[c.id] = PlaceMonitor(place, tuning);
      } else if (mon.place?.center.lat != place.center.lat || mon.place?.center.lng != place.center.lng) {
        mon.placeChanged(place);
      }
    }
    customMonitors.removeWhere((id, _) => !keep.contains(id));
    _customModes.removeWhere((id, _) => !keep.contains(id));
  }

  Iterable<PlaceMonitor> get _allMonitors => [...monitors.values, ...customMonitors.values];

  DateTime? _startedAt;
  CatMode _mode = CatMode.starting;

  CatMode get mode => _mode;

  void start(DateTime now) {
    motion.reset();
    for (final m in _allMonitors) {
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
      for (final e in customMonitors.entries) {
        final ev = e.value.addFix(f, snap);
        if (ev != null) events.add('pin:$ev');
      }
    }
    return events;
  }

  ActivitySnapshot evaluate(DateTime now) {
    final m = motion.snapshot(now);
    CatMode mode;
    final here = _priority.where((k) => monitor(k).present).firstOrNull;
    final pin = customMonitors.entries.where((e) => e.value.present).firstOrNull;
    if (here != null) {
      // Being at a place beats the ordinary modes, and survives indoor GPS loss.
      mode = modeAt(here);
    } else if (pin != null) {
      mode = _customModes[pin.key]!;
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
    if (_allMonitors.any((p) => p.present)) return m.kind == MotionKind.stationary;
    return m.kind == MotionKind.stationary &&
        m.stationarySince != null &&
        now.difference(m.stationarySince!) >= tuning.slowSamplingAfter;
  }
}
