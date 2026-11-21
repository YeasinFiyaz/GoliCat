import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/place_store.dart';
import 'package:golicat/share/share_controller.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/tracking/fix.dart';
import 'package:golicat/tracking/location_service.dart';
import 'package:golicat/tracking/trip_backend.dart';
import 'package:golicat/tracking/trip_runner.dart';
import 'package:golicat/ui/trip_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GPS without the plugin.
class FakeLocation implements LocationSource {
  final _fixes = StreamController<LocationFix>.broadcast();
  final _problems = StreamController<LocationProblem>.broadcast();
  bool started = false, slow = false;
  LocationProblem permission = LocationProblem.none;

  @override
  Stream<LocationFix> get fixes => _fixes.stream;
  @override
  Stream<LocationProblem> get problems => _problems.stream;
  @override
  Future<LocationProblem> ensurePermission() async => permission;
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> setSlow(bool s) async => slow = s;
  @override
  Future<void> stop() async => started = false;
  @override
  void dispose() {}

  void fix(DateTime at, double lat, double lng, {double speed = 0, double acc = 8}) =>
      _fixes.add(LocationFix(point: GeoPoint(lat, lng), time: at, accuracy: acc, speed: speed, speedAccuracy: 1, heading: 90));
}

Future<AppStore> freshStore() async {
  SharedPreferences.setMockInitialValues({'seeded': true});
  return AppStore.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runner: start → fixes → status → stop returns the journal and clears the flag', () async {
    final store = await freshStore();
    final loc = FakeLocation();
    var now = DateTime(2026, 11, 21, 9);
    final posts = <String>[];
    final share = ShareController(store,
        clock: () => now,
        baseUrl: 'https://x.test',
        client: MockClient((r) async {
          posts.add(r.method);
          return http.Response('{"status":"live","until":0}', 200);
        }));
    final runner = TripRunner(store, location: loc, share: share, clock: () => now);
    final seen = <Map<String, dynamic>>[];
    runner.onStatus = seen.add;

    expect(await runner.start(), LocationProblem.none);
    expect(loc.started, isTrue);
    expect(store.tripRunning, isTrue);
    expect(store.activeTrip, isNotNull);
    expect(TripStatus(seen.last).hasFix, isFalse);

    loc.fix(now, 23.78, 90.39);
    await Future<void>.delayed(Duration.zero);
    final st = TripStatus(seen.last);
    expect(st.running, isTrue);
    expect(st.hasFix, isTrue);
    expect(st.lat, closeTo(23.78, 1e-9));
    expect(st.mode, isNot(CatMode.starting));

    // Starting a share is reported in the status and reaches the relay.
    final link = await runner.startShare(duration: const Duration(minutes: 15));
    expect(link, startsWith('https://x.test/s/'));
    expect(TripStatus(seen.last).shareActive, isTrue);
    expect(posts, contains('POST'));

    final log = await runner.stop();
    expect(log, isNotNull);
    expect(log!.endedAt, isNotNull);
    expect(loc.started, isFalse);
    expect(store.tripRunning, isFalse);
    expect(store.activeTrip, isNull);
    expect(share.active, isFalse);
    expect(seen.last['running'], isFalse);
    expect(seen.last['log'], isNotNull);
  });

  test('runner: resume continues the saved journal instead of starting over', () async {
    final store = await freshStore();
    final loc = FakeLocation();
    var now = DateTime(2026, 11, 21, 9);
    final r1 = TripRunner(store, location: loc, share: ShareController(store, client: MockClient((_) async => http.Response('', 500))), clock: () => now);
    await r1.start();
    loc.fix(now, 23.78, 90.39);
    await Future<void>.delayed(Duration.zero);
    final started = TripStatus(r1.status()).startedAt;
    // The service dies without stop(): journal + flag stay behind.
    now = now.add(const Duration(minutes: 5));
    final r2 = TripRunner(store, location: FakeLocation(), share: ShareController(store, client: MockClient((_) async => http.Response('', 500))), clock: () => now);
    await r2.start(resume: true);
    expect(TripStatus(r2.status()).startedAt, started);
    await r2.stop();
  });

  test('runner: refuses to start without permission', () async {
    final store = await freshStore();
    final loc = FakeLocation()..permission = LocationProblem.deniedForever;
    final runner = TripRunner(store, location: loc, share: ShareController(store, client: MockClient((_) async => http.Response('', 500))));
    expect(await runner.start(), LocationProblem.deniedForever);
    expect(runner.running, isFalse);
    expect(store.tripRunning, isFalse);
  });

  test('controller mirrors the backend: state, cat position, share, end()', () async {
    final store = await freshStore();
    final loc = FakeLocation();
    var now = DateTime(2026, 11, 21, 9);
    final backend = LocalBackend(store,
        location: loc,
        share: ShareController(store,
            clock: () => now,
            baseUrl: 'https://x.test',
            client: MockClient((r) async {
              // The relay echoes the requested expiry.
              final until = r.body.contains('"until"') ? RegExp(r'"until":(\d+)').firstMatch(r.body)?.group(1) : null;
              return http.Response('{"status":"live","until":${until ?? 0}}', 200);
            })),
        clock: () => now);
    final trip = TripController(store, backend: backend, permissions: _NoPermissionPrompt(), clock: () => now);
    var notified = 0;
    trip.addListener(() => notified++);

    expect(await trip.start(), LocationProblem.none);
    expect(trip.active, isTrue);
    expect(trip.position, isNull);

    loc.fix(now, 23.78, 90.39, speed: 1.5);
    await Future<void>.delayed(Duration.zero);
    expect(trip.position?.lat, closeTo(23.78, 1e-9));
    expect(trip.mirror.position.shown, isNotNull);
    expect(trip.status?.label, isNotEmpty);
    expect(notified, greaterThan(1));

    final link = await trip.startShare(duration: const Duration(hours: 1));
    expect(link, startsWith('https://x.test/s/'));
    expect(trip.shareActive, isTrue);
    expect(trip.shareUntil, now.add(const Duration(hours: 1)));
    await trip.stopShare();
    expect(trip.shareActive, isFalse);

    final log = await trip.end();
    expect(log, isNotNull);
    expect(trip.active, isFalse);
    expect(await trip.interruptedTrip(), isNull);
    trip.dispose();
  });

  test('controller: journal left by a dead service counts as interrupted', () async {
    final store = await freshStore();
    final loc = FakeLocation();
    final b1 = LocalBackend(store, location: loc, share: ShareController(store, client: MockClient((_) async => http.Response('', 500))));
    await b1.runner.start();
    loc.fix(DateTime.now(), 23.78, 90.39);
    await Future<void>.delayed(Duration.zero);
    // New process, backend not running, flag + journal remain.
    final trip = TripController(store,
        backend: LocalBackend(store, location: FakeLocation(), share: ShareController(store, client: MockClient((_) async => http.Response('', 500)))),
        permissions: _NoPermissionPrompt());
    await trip.attach();
    expect(trip.active, isFalse);
    final log = await trip.interruptedTrip();
    expect(log, isNotNull);
    expect(store.tripRunning, isFalse);
    trip.dispose();
  });
}

class _NoPermissionPrompt extends LocationService {
  @override
  Future<LocationProblem> ensurePermission() async => LocationProblem.none;
  @override
  Future<void> ensureNotificationPermission() async {}
}
