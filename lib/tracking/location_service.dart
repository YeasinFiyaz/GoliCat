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
class LocationService implements LocationSource {
  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  bool _slow = false;
  bool get running => _sub != null;

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

  /// Android 13+ needs notification permission to show the "roaming" notice.
  Future<void> ensureNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final st = await ph.Permission.notification.status;
    if (!st.isGranted) await ph.Permission.notification.request();
  }

  @override
  Future<void> start() async {
    _slow = false;
    await _listen();
    _serviceSub ??= _serviceStream()?.listen((s) {
      if (s == ServiceStatus.disabled) _problems.add(LocationProblem.serviceOff);
      if (s == ServiceStatus.enabled) {
        _problems.add(LocationProblem.none);
        _listen();
      }
    });
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
    if (slow == _slow || _sub == null) return;
    _slow = slow;
    await _listen();
  }

  Future<void> _listen() async {
    await _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      (pos) => _fixes.add(LocationFix(
        point: GeoPoint(pos.latitude, pos.longitude),
        time: pos.timestamp.toLocal(),
        accuracy: pos.accuracy <= 0 ? 999 : pos.accuracy,
        speed: pos.speed,
        speedAccuracy: pos.speedAccuracy > 0 ? pos.speedAccuracy : -1,
        heading: pos.heading,
      )),
      onError: (Object e) {
        if (e is LocationServiceDisabledException) {
          _problems.add(LocationProblem.serviceOff);
        } else if (e is PermissionDeniedException) {
          _problems.add(LocationProblem.denied);
        } else {
          _problems.add(LocationProblem.error);
        }
      },
      cancelOnError: false,
    );
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: Duration(milliseconds: _slow ? 8000 : 1000),
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
