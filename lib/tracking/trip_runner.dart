import 'dart:async';
import 'dart:convert';

import '../places/place_store.dart';
import '../share/share_controller.dart';
import 'activity_engine.dart';
import 'fix.dart';
import 'location_service.dart';
import 'place_monitor.dart';
import 'roam_session.dart';
import 'trip_recorder.dart';

/// Everything a trip needs, with no UI: GPS → engine → journal → live share.
/// Runs inside the Android foreground service (so it survives the app being
/// swiped away) or in-process on other platforms. Reports a plain-map status
/// once a second through [onStatus].
class TripRunner {
  TripRunner(this.store, {LocationSource? location, ShareController? share, DateTime Function()? clock})
      : location = location ?? LocationService(),
        clock = clock ?? DateTime.now {
    this.share = share ?? ShareController(store);
  }

  final AppStore store;
  final LocationSource location;
  final DateTime Function() clock;
  late final ShareController share;

  RoamSession? session;
  LocationProblem problem = LocationProblem.none;
  StreamSubscription<LocationFix>? _fixSub;
  StreamSubscription<LocationProblem>? _probSub;
  Timer? _tick;

  void Function(Map<String, dynamic> status)? onStatus;

  bool get running => session != null;

  /// Trips are never endless: a forgotten trip stops by itself after this.
  static const maxTrip = Duration(hours: 24);

  /// Starts a new trip, or continues the journalled one when [resume] is set
  /// (the service was restarted by Android, or the app was reopened).
  Future<LocationProblem> start({bool resume = false}) async {
    if (session != null) return problem;
    final p = await location.ensurePermission();
    problem = p;
    if (p != LocationProblem.none && p != LocationProblem.approximate) return p;
    TripLog? previous;
    if (resume && store.activeTrip != null) {
      try {
        previous = TripLog.fromJson(store.activeTrip!);
      } catch (_) {}
    }
    session = RoamSession(
      clock: clock,
      office: store.place(PlaceKind.office),
      home: store.place(PlaceKind.home),
      reducedMotion: store.reducedMotion,
      previous: previous,
    );
    session!.onJournalChanged = _saveJournal;
    _fixSub = location.fixes.listen(_onFix);
    _probSub = location.problems.listen((pr) {
      problem = pr;
      _emit();
    });
    await location.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    await store.setTripRunning(true);
    _saveJournal();
    _emit();
    return p;
  }

  void _onFix(LocationFix f) {
    if (problem == LocationProblem.serviceOff || problem == LocationProblem.error) {
      problem = LocationProblem.none;
    }
    session?.addFix(f);
    _emit();
  }

  Future<void> _onTick() async {
    final s = session;
    if (s == null) return;
    s.evaluate();
    s.director.update(1.0); // headless: keeps the journal's clip history honest
    final slow = s.engine.wantsSlowSampling(clock());
    s.engine.motion.slowSampling = slow;
    await location.setSlow(slow);
    await share.tick(s);
    if (clock().difference(s.log.startedAt) > maxTrip) {
      await stop();
      return;
    }
    _emit();
  }

  void placeChanged(PlaceKind k) {
    session?.setPlace(k.label, store.place(k));
    _emit();
  }

  /// Starts a live share; null duration = until the trip ends. Returns the link, or null.
  Future<String?> startShare({Duration? duration}) async {
    final s = session;
    if (s == null) return null;
    final ok = await share.start(duration: duration, now: ShareController.stateOf(s));
    _emit();
    return ok ? share.link : null;
  }

  Future<void> stopShare() async {
    await share.stop();
    _emit();
  }

  void _saveJournal() {
    final s = session;
    if (s == null) return;
    store.saveActiveTrip(s.log.toJson());
  }

  /// Ends the trip and the share. Returns the journal for the comic.
  Future<TripLog?> stop() async {
    _tick?.cancel();
    _tick = null;
    await _fixSub?.cancel();
    await _probSub?.cancel();
    _fixSub = null;
    _probSub = null;
    if (share.active) await share.stop();
    await location.stop();
    final log = session?.finish();
    session = null;
    await store.saveActiveTrip(null);
    await store.setTripRunning(false);
    onStatus?.call({'running': false, if (log != null) 'log': log.toJson()});
    return log;
  }

  void emit() => onStatus?.call(status());
  void _emit() => emit();

  /// The whole trip as plain data (goes over the service channel).
  Map<String, dynamic> status() {
    final s = session;
    if (s == null) return {'running': false};
    final snap = s.snap;
    final m = snap?.motion;
    return {
      'running': true,
      'startedAt': s.log.startedAt.millisecondsSinceEpoch,
      'distanceM': s.log.distanceM,
      'problem': problem.name,
      'mode': (snap?.mode ?? CatMode.starting).name,
      'label': s.director.label,
      'lat': snap?.position?.lat,
      'lng': snap?.position?.lng,
      'acc': m?.lastAccuracy,
      'speed': m?.speed,
      'heading': m?.headingDeg,
      'moving': m?.moving ?? false,
      'lastFixAt': m?.lastFixAt?.millisecondsSinceEpoch,
      'sinceUpdateMs': snap?.sinceUpdate?.inMilliseconds,
      'officePhase': (snap?.officePhase ?? PlacePhase.outside).name,
      'homePhase': (snap?.homePhase ?? PlacePhase.outside).name,
      'share': {
        'active': share.active,
        'link': share.link,
        'until': share.until?.millisecondsSinceEpoch,
        'untilTripEnds': share.untilTripEnds,
        'failing': share.failing,
      },
    };
  }

  /// Used by the notification: "কাজে আছি · At work · sharing until 7:39 PM".
  String notificationText() {
    final s = session;
    if (s == null) return 'Roaming with you';
    final parts = [s.director.label];
    if (share.active) {
      parts.add(share.untilTripEnds
          ? 'sharing live until the trip ends'
          : 'sharing live until ${_hm(share.until!)}');
    }
    parts.add('Open GoliCat to end the trip');
    return parts.join(' · ');
  }

  static String _hm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> dispose() async {
    _tick?.cancel();
    await _fixSub?.cancel();
    await _probSub?.cancel();
    location.dispose();
    share.dispose();
  }
}

/// Parsed form of [TripRunner.status] for the UI.
class TripStatus {
  TripStatus(this.raw);
  final Map<String, dynamic> raw;

  bool get running => raw['running'] == true;
  CatMode get mode => CatMode.values.firstWhere((m) => m.name == raw['mode'], orElse: () => CatMode.starting);
  String get label => raw['label'] as String? ?? '';
  LocationProblem get problem =>
      LocationProblem.values.firstWhere((p) => p.name == raw['problem'], orElse: () => LocationProblem.none);
  double? get lat => (raw['lat'] as num?)?.toDouble();
  double? get lng => (raw['lng'] as num?)?.toDouble();
  double get accuracy => (raw['acc'] as num?)?.toDouble() ?? 0;
  double get speed => (raw['speed'] as num?)?.toDouble() ?? 0;
  double get headingDeg => (raw['heading'] as num?)?.toDouble() ?? 0;
  bool get moving => raw['moving'] == true;
  bool get hasFix => raw['lastFixAt'] != null;
  Duration? get sinceUpdate =>
      raw['sinceUpdateMs'] == null ? null : Duration(milliseconds: (raw['sinceUpdateMs'] as num).toInt());
  PlacePhase get officePhase =>
      PlacePhase.values.firstWhere((p) => p.name == raw['officePhase'], orElse: () => PlacePhase.outside);
  PlacePhase get homePhase =>
      PlacePhase.values.firstWhere((p) => p.name == raw['homePhase'], orElse: () => PlacePhase.outside);
  DateTime? get startedAt =>
      raw['startedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((raw['startedAt'] as num).toInt());

  Map<String, dynamic> get _share => (raw['share'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool get shareActive => _share['active'] == true;
  String? get shareLink => _share['link'] as String?;
  DateTime? get shareUntil =>
      _share['until'] == null ? null : DateTime.fromMillisecondsSinceEpoch((_share['until'] as num).toInt());
  bool get shareUntilTripEnds => _share['untilTripEnds'] == true;
  bool get shareFailing => _share['failing'] == true;

  String toJson() => jsonEncode(raw);
}

/// So tests can feed fixes without the geolocator plugin.
abstract class LocationSource {
  Stream<LocationFix> get fixes;
  Stream<LocationProblem> get problems;
  Future<LocationProblem> ensurePermission();
  Future<void> start();
  Future<void> setSlow(bool slow);
  Future<void> stop();
  void dispose();
}
