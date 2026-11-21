import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../places/place_store.dart';
import '../tracking/location_service.dart';
import '../tracking/trip_backend.dart';
import '../tracking/trip_mirror.dart';
import '../tracking/trip_recorder.dart';
import '../tracking/trip_runner.dart';
import '../tracking/trip_service.dart';

enum TripState { idle, starting, active }

/// The screen's handle on the real (non-demo) trip. The trip itself runs in
/// a [TripBackend] (the Android foreground service, or in-process); this
/// mirrors its status and relays the user's commands.
class TripController extends ChangeNotifier {
  TripController(this.store, {TripBackend? backend, LocationService? permissions, DateTime Function()? clock})
      : backend = backend ?? _defaultBackend(store),
        permissions = permissions ?? LocationService(),
        mirror = TripMirror(clock: clock) {
    _sub = this.backend.status.listen(_onStatus);
  }

  static TripBackend _defaultBackend(AppStore store) =>
      defaultTargetPlatform == TargetPlatform.android ? ServiceBackend(store) : LocalBackend(store);

  final AppStore store;
  final TripBackend backend;

  /// Only for asking permission and opening settings from the screen.
  final LocationService permissions;

  /// What the cat on screen follows.
  final TripMirror mirror;

  TripState state = TripState.idle;
  LocationProblem problem = LocationProblem.none;
  TripStatus? status;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Completer<TripLog?>? _ending;

  bool get active => state == TripState.active;
  GeoPoint? get position => mirror.point;

  bool get shareActive => status?.shareActive ?? false;
  String? get shareLink => status?.shareLink;
  DateTime? get shareUntil => status?.shareUntil;
  bool get shareUntilTripEnds => status?.shareUntilTripEnds ?? false;
  bool get shareFailing => status?.shareFailing ?? false;

  /// Call once at startup: picks up a trip the service kept running while
  /// the app was closed.
  Future<void> attach() async {
    if (await backend.isRunning()) {
      state = TripState.active;
      await backend.send('status');
      notifyListeners();
    }
  }

  /// A journal left behind by a trip that died with the app (service not
  /// running any more, journal still saved).
  Future<TripLog?> interruptedTrip() async {
    if (active || await backend.isRunning()) return null;
    await store.reload();
    final raw = store.activeTrip;
    if (raw == null) return null;
    await store.setTripRunning(false);
    return TripLog.fromJson(raw);
  }

  /// Returns the problem (none = started).
  Future<LocationProblem> start() async {
    state = TripState.starting;
    notifyListeners();
    final p = await permissions.ensurePermission();
    problem = p;
    if (p != LocationProblem.none && p != LocationProblem.approximate) {
      state = TripState.idle;
      notifyListeners();
      return p;
    }
    await permissions.ensureNotificationPermission();
    mirror.reset();
    status = null;
    await backend.send('start');
    state = TripState.active;
    notifyListeners();
    return p;
  }

  void _onStatus(Map<String, dynamic> raw) {
    final st = TripStatus(raw);
    if (!st.running) {
      final log = raw['log'] == null ? null : TripLog.fromJson(raw['log'] as String);
      status = null;
      state = TripState.idle;
      _ending?.complete(log);
      _ending = null;
      notifyListeners();
      return;
    }
    status = st;
    problem = st.problem;
    if (state != TripState.active) state = TripState.active;
    if (st.hasFix) mirror.apply(st);
    notifyListeners();
  }

  void placeChanged(PlaceKind k) {
    if (active) backend.send('place', {'kind': k.name});
  }

  /// Starts a live share; returns the link, or null when the server could
  /// not be reached.
  Future<String?> startShare({Duration? duration}) async {
    final next = backend.status.first.timeout(const Duration(seconds: 15));
    await backend.send('startShare', {if (duration != null) 'minutes': duration.inMinutes});
    try {
      return TripStatus(await next).shareLink;
    } catch (_) {
      return null;
    }
  }

  Future<void> stopShare() async {
    final next = backend.status.first.timeout(const Duration(seconds: 10));
    await backend.send('stopShare');
    try {
      await next;
    } catch (_) {}
  }

  /// Stops tracking completely and returns the trip journal.
  Future<TripLog?> end() async {
    if (!active) return null;
    final c = _ending = Completer<TripLog?>();
    await backend.send('stop');
    try {
      return await c.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      // The service didn't answer: fall back to the saved journal.
      _ending = null;
      await store.reload();
      final raw = store.activeTrip;
      await store.saveActiveTrip(null);
      await store.setTripRunning(false);
      state = TripState.idle;
      status = null;
      notifyListeners();
      if (raw == null) return null;
      final log = TripLog.fromJson(raw);
      log?.endedAt = DateTime.now();
      return log;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    backend.dispose();
    super.dispose();
  }
}
