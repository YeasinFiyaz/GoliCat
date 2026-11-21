import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/place_store.dart';
import 'package:golicat/share/share_controller.dart';
import 'package:golicat/share/share_state.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/tracking/fix.dart';
import 'package:golicat/tracking/roam_session.dart';
import 'package:golicat/ui/theme.dart';
import 'package:golicat/viewer/viewer_screen.dart';
import 'package:golicat/viewer/viewer_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake relay that behaves like share/src/worker.js.
class FakeRelay {
  final requests = <http.Request>[];
  final tokens = <String, String>{};
  final states = <String, Map<String, dynamic>>{};
  final ended = <String>{};
  bool down = false;

  late final client = MockClient((req) async {
    requests.add(req);
    if (down) throw http.ClientException('offline');
    final id = req.url.pathSegments.last;
    final tok = (req.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
    if (req.method == 'GET') {
      if (ended.contains(id)) return http.Response('{"status":"ended"}', 410);
      if (!tokens.containsKey(id)) return http.Response('{"status":"unknown"}', 404);
      return http.Response(jsonEncode({'status': 'live', 'until': 9e12, 'state': states[id]}), 200);
    }
    if (tokens.containsKey(id) && tokens[id] != tok) return http.Response('{}', 403);
    if (req.method == 'DELETE') {
      ended.add(id);
      states.remove(id);
      return http.Response('{"status":"ended"}', 200);
    }
    if (ended.contains(id)) return http.Response('{}', 410);
    tokens[id] = tok;
    final b = jsonDecode(req.body) as Map<String, dynamic>;
    if (b['lat'] != null) states[id] = {...b, 'ts': DateTime.now().millisecondsSinceEpoch};
    return http.Response(jsonEncode({'status': 'live', 'until': b['until'] ?? 4e12}), 200);
  });

  int posts(String id) => requests.where((r) => r.method == 'POST' && r.url.pathSegments.last == id).length;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'seeded': true}));

  group('ShareController', () {
    late DateTime now;
    late AppStore store;
    late FakeRelay relay;
    late RoamSession session;
    const home = GeoPoint(23.79, 90.35);

    void fix(GeoPoint p, {double speed = 0}) => session.addFix(
        LocationFix(point: p, time: now, accuracy: 6, speed: speed, speedAccuracy: 0.5));

    setUp(() async {
      now = DateTime(2026, 11, 21, 17);
      store = await AppStore.load();
      relay = FakeRelay();
      session = RoamSession(clock: () => now);
      fix(home);
    });

    ShareController make() =>
        ShareController(store, client: relay.client, clock: () => now, baseUrl: 'https://relay.test');

    test('start makes a fresh unguessable link and sends the first position', () async {
      final c = make();
      expect(await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session)), isTrue);
      expect(c.active, isTrue);
      expect(c.id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(c.link, 'https://relay.test/s/${c.id}');
      expect(relay.states[c.id]!['lat'], closeTo(23.79, 1e-6));
      // The token is never part of the link.
      expect(c.link!.contains(relay.tokens[c.id]!), isFalse);
      final first = c.id;
      await c.start(duration: const Duration(hours: 1));
      expect(c.id, isNot(first), reason: 'every share gets a new link');
      expect(relay.ended, contains(first), reason: 'starting again ends the old link');
    });

    test('pushes every 15 s while still, every 5 s while moving', () async {
      final c = make();
      await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session));
      final id = c.id!;
      for (var s = 0; s < 30; s++) {
        now = now.add(const Duration(seconds: 1));
        fix(home);
        await c.tick(session);
      }
      expect(relay.posts(id), 1 + 2, reason: 'start + two 15 s heartbeats');
      // Walk east at 1.4 m/s; once walking is confirmed, count 30 s of pushes.
      var east = 0.0;
      Future<void> walk(int secs) async {
        for (var s = 0; s < secs; s++) {
          now = now.add(const Duration(seconds: 1));
          east += 1.4;
          fix(offsetM(home, east, 0), speed: 1.4);
          await c.tick(session);
        }
      }
      await walk(15);
      expect(session.snap!.motion.moving, isTrue);
      final before = relay.posts(id);
      await walk(30);
      expect(relay.posts(id) - before, inInclusiveRange(6, 7));
    });

    test('mode change is sent quickly', () async {
      final c = make();
      await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session));
      final id = c.id!;
      // Stand still past the cha-break delay: idle → waiting (tea).
      for (var s = 0; s < 70; s++) {
        now = now.add(const Duration(seconds: 1));
        fix(home);
        await c.tick(session);
      }
      expect(session.snap!.mode, CatMode.waiting);
      expect(relay.states[id]!['mode'], 'waiting');
    });

    test('expires by itself, and survives an app restart until stopped', () async {
      final c = make();
      await c.start(duration: const Duration(minutes: 15), now: ShareController.stateOf(session));
      final id = c.id!;
      final again = make();
      expect(again.id, id, reason: 'restored after restart');
      now = now.add(const Duration(minutes: 16));
      await again.tick(session);
      expect(again.active, isFalse);
      expect(relay.ended, contains(id));
      expect(store.shareJson, isNull);
    });

    test('offline: keeps the share and marks failing, recovers later', () async {
      final c = make();
      await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session));
      relay.down = true;
      now = now.add(const Duration(seconds: 20));
      await c.tick(session);
      expect(c.failing, isTrue);
      expect(c.active, isTrue);
      relay.down = false;
      now = now.add(const Duration(seconds: 11));
      await c.tick(session);
      expect(c.failing, isFalse);
    });

    test('stop deletes it on the server and forgets the token', () async {
      final c = make();
      await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session));
      final id = c.id!;
      await c.stop();
      expect(c.active, isFalse);
      expect(relay.ended, contains(id));
      expect(relay.states[id], isNull);
      expect(store.shareJson, isNull);
    });

    test('ended elsewhere (410) clears the share', () async {
      final c = make();
      await c.start(duration: const Duration(hours: 1), now: ShareController.stateOf(session));
      relay.ended.add(c.id!);
      now = now.add(const Duration(seconds: 20));
      await c.tick(session);
      expect(c.active, isFalse);
    });

    test('payload has the position and mode only', () {
      final st = ShareController.stateOf(session)!;
      expect(st.toJson().keys.toSet(), {'lat', 'lng', 'acc', 'heading', 'speed', 'moving', 'mode'});
    });
  });

  group('ViewerSession', () {
    test('turns into "lost" when the phone goes quiet', () {
      var now = DateTime(2026, 11, 21, 17);
      final v = ViewerSession(clock: () => now);
      v.apply(ShareState(point: const GeoPoint(23.78, 90.39), mode: CatMode.atWork, at: now));
      expect(v.director.mode, CatMode.atWork);
      now = now.add(const Duration(seconds: 80));
      v.refresh();
      expect(v.stale, isTrue);
      expect(v.director.mode, CatMode.lost);
    });
  });

  testWidgets('viewer shows the live cat, then "ended"', (tester) async {
    final relay = FakeRelay();
    const id = 'AAAAAAAAAAAAAAAAAAAAAA';
    relay.tokens[id] = 't';
    relay.states[id] = {
      'lat': 23.7801,
      'lng': 90.394,
      'acc': 5.0,
      'mode': 'atWork',
      'moving': false,
      'speed': 0.0,
      'heading': 0.0,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    await tester.pumpWidget(MaterialApp(
      theme: GoliTheme.light(),
      home: ViewerScreen(
          shareId: id,
          api: Uri.parse('https://relay.test/api/s/'),
          client: relay.client,
          pollEvery: const Duration(seconds: 3),
          showTiles: false),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('At work'), findsOneWidget);
    expect(find.textContaining('±5 m'), findsOneWidget);

    relay.ended.add(id);
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Sharing has ended'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('viewer explains a bad link', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoliTheme.light(),
      home: ViewerScreen(shareId: null, api: Uri.parse('https://relay.test/api/s/'), showTiles: false),
    ));
    await tester.pump();
    expect(find.text('This link isn\'t live'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
