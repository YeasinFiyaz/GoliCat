import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../core/geo.dart';
import 'fix.dart';
import 'trip_runner.dart';

enum LocationProblem { none, serviceOff, denied, deniedForever, approximate, error }

/// Wraps geolocator: permission, service checks, and a position stream whose
/// sampling slows down when the cat is settled. Optionally keeps running when
/// the screen is locked (Android foreground service / iOS background updates).
///
/// The stream heals itself: if it errors, ends, or simply goes quiet (which
/// happens on some phones when the network drops), it is re-opened with a
/// short back-off. After repeated silence on Android it switches from the
/// fused provider to the plain GPS provider, which needs no network.
class LocationService implements LocationSource {
  LocationService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Timer? _watchdog;
  Timer? _retry;
  bool _slow = false;
  bool _running = false;
  int _generation = 0;
  int _restarts = 0;
  int _silentRestarts = 0;
  bool _useLocationManager = false;
  DateTime? _lastFixAt;
  DateTime? _listenedAt;

  bool get running => _running;

  /// Fixes expected at least this often; longer silence restarts the stream.
  static const quietLimit = Duration(seconds: 20);
  static const quietLimitSlow = Duration(seconds: 40);

  /// After this many restarts without a single fix, use the GPS provider directly.
  static const silentRestartsBeforeGps = 2;

  final _fixes = StreamController<LocationFix>.broadcast();
  final _problems = StreamController<LocationProblem>.broadcast();
  @override
  Stream<LocationFix> get fixes => _fixes.stream;
  @override
  Stream<LocationProblem> get problems => _problems.stream;

  /// Checks service + permission, requesting permission if needed.
  @override
  Future<LocationProblem> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationProblem.serviceOff;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) return LocationProblem.deniedForever;
    if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
      return LocationProblem.denied;
    }
    try {
      final acc = await Geolocator.getLocationAccuracy();
      if (acc == LocationAccuracyStatus.reduced) return LocationProblem.approximate;
    } catch (_) {}
    return LocationProblem.none;
  }

  /// Like [ensurePermission] but never asks: for refreshing a banner.
  Future<LocationProblem> checkProblem() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationProblem.serviceOff;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) return LocationProblem.deniedForever;
    if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
      return LocationProblem.denied;
    }
    return LocationProblem.none;
  }

  /// Android 13+ needs notification permission to show the "roaming" notice.
  Future<void> ensureNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final st = await ph.Permission.notification.status;
    if (!st.isGranted) await ph.Permission.notification.request();
  }

  @override
  Future<void> start() async {
    _slow = false;
    _running = true;
    _restarts = 0;
    _silentRestarts = 0;
    _useLocationManager = false;
    _lastFixAt = null;
    await _listen();
    _serviceSub ??= _serviceStream()?.listen((s) {
      if (!_running) return;
      if (s == ServiceStatus.disabled) _report(LocationProblem.serviceOff);
      if (s == ServiceStatus.enabled) {
        _report(LocationProblem.none);
        _listen();
      }
    });
    _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) => _checkQuiet());
  }

  Stream<ServiceStatus>? _serviceStream() {
    try {
      return Geolocator.getServiceStatusStream();
    } catch (_) {
      return null; // not supported on this platform
    }
  }

  /// Switch sampling rate. Restarts the stream only when it actually changes.
  @override
  Future<void> setSlow(bool slow) async {
    if (slow == _slow || !_running) return;
    _slow = slow;
    await _listen();
  }

  Future<void> _listen() async {
    if (!_running) return;
    _retry?.cancel();
    _retry = null;
    final gen = ++_generation;
    await _sub?.cancel();
    _sub = null;
    if (!_running || gen != _generation) return;
    _listenedAt = _clock();
    try {
      _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (pos) {
          if (gen != _generation) return;
          _lastFixAt = _clock();
          _restarts = 0;
          _silentRestarts = 0;
          _fixes.add(LocationFix(
            point: GeoPoint(pos.latitude, pos.longitude),
            time: pos.timestamp.toLocal(),
            accuracy: pos.accuracy <= 0 ? 999 : pos.accuracy,
            speed: pos.speed,
            speedAccuracy: pos.speedAccuracy > 0 ? pos.speedAccuracy : -1,
            heading: pos.heading,
          ));
        },
        onError: (Object e) {
          if (gen != _generation) return;
          if (e is LocationServiceDisabledException) {
            _report(LocationProblem.serviceOff);
            // The service-status stream re-opens us when location comes back.
            return;
          }
          if (e is PermissionDeniedException) {
            _report(LocationProblem.denied);
            return;
          }
          _report(LocationProblem.error);
          _scheduleRestart();
        },
        onDone: () {
          // The platform closed the stream under us: open it again.
          if (gen == _generation) _scheduleRestart();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _report(LocationProblem.error);
      _scheduleRestart();
    }
  }

  /// Re-opens the stream after a short, growing pause (2 s, 4 s, … 30 s).
  void _scheduleRestart() {
    if (!_running || _retry != null) return;
    final secs = (2 << _restarts.clamp(0, 4)).clamp(2, 30);
    _restarts++;
    _retry = Timer(Duration(seconds: secs), () {
      _retry = null;
      _listen();
    });
  }

  /// Fixes stopped arriving although nothing reported an error: restart.
  void _checkQuiet() {
    if (!_running || _retry != null) return;
    final now = _clock();
    final since = now.difference(_lastFixAt ?? _listenedAt ?? now);
    if (since < (_slow ? quietLimitSlow : quietLimit)) return;
    _silentRestarts++;
    if (_silentRestarts >= silentRestartsBeforeGps) _useLocationManager = true;
    _listen();
  }

  void _report(LocationProblem p) {
    if (!_problems.isClosed) _problems.add(p);
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: Duration(milliseconds: _slow ? 8000 : 1000),
        // Plain GPS when the fused provider has gone quiet (e.g. no network).
        forceLocationManager: _useLocationManager,
        // The trip's own foreground service (TripService) carries the notification.
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        // "high" = nearest ten metres on iOS: still street-level, easier on the battery.
        accuracy: _slow ? LocationAccuracy.high : LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
  }

  @override
  Future<void> stop() async {
    _running = false;
    _generation++;
    _watchdog?.cancel();
    _watchdog = null;
    _retry?.cancel();
    _retry = null;
    await _sub?.cancel();
    _sub = null;
    await _serviceSub?.cancel();
    _serviceSub = null;
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  void dispose() {
    stop();
    _fixes.close();
    _problems.close();
  }
}
