import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_director.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/cat/pose.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/custom_place.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/tracking/fix.dart';

final _t0 = DateTime(2026, 1, 1, 9);
const _o = GeoPoint(23.78, 90.39);

LocationFix _fx(int s, double e, double n) =>
    LocationFix(point: offsetM(_o, e, n), time: _t0.add(Duration(seconds: s)), accuracy: 10);

CustomPlace _pin(String icon, {String id = 'p1', double east = 0}) =>
    CustomPlace(id: id, name: icon, icon: icon, center: offsetM(_o, east, 0));

/// Walks in from 150 m away, then stays; returns the second the mode became [want].
int? _arrival(ActivityEngine e, CatMode want) {
  e.start(_t0);
  for (var s = 0; s <= 400; s++) {
    final east = s < 60 ? -150 + s * 2.5 : 0.0;
    e.addFix(_fx(s, east, 0));
    if (e.evaluate(_t0.add(Duration(seconds: s))).mode == want) return s;
  }
  return null;
}

void main() {
  group('pins from More places', () {
    test('each activity pin starts its scene about a minute after arriving', () {
      for (final (icon, mode) in [
        ('bazar', CatMode.atBazar),
        ('food', CatMode.eatingOut),
        ('bus', CatMode.atBusStop),
        ('park', CatMode.atPark),
        ('work', CatMode.atWork),
        ('school', CatMode.studying),
        ('home', CatMode.atHome),
        ('friends', CatMode.hangingOut),
      ]) {
        final at = _arrival(ActivityEngine(custom: [_pin(icon)]), mode);
        expect(at, isNotNull, reason: icon);
        expect(at!, inInclusiveRange(60, 160), reason: icon);
      }
    });

    test('prayer places never start an activity', () {
      for (final icon in ['mosque', 'temple', 'church']) {
        expect(ActivityEngine.modeForIcon(icon), isNull);
        final e = ActivityEngine(custom: [_pin(icon)]);
        expect(e.customMonitors, isEmpty, reason: icon);
        expect(_arrival(e, CatMode.atBazar), isNull);
      }
    });

    test('a pin removed mid-trip lets the cat leave the scene', () {
      final e = ActivityEngine(custom: [_pin('park')]);
      expect(_arrival(e, CatMode.atPark), isNotNull);
      e.setCustomPlaces(const []);
      expect(e.evaluate(_t0.add(const Duration(seconds: 401))).mode, isNot(CatMode.atPark));
    });

    test('an unchanged pin keeps its arrival when the list is saved again', () {
      final pin = _pin('bazar');
      final e = ActivityEngine(custom: [pin]);
      expect(_arrival(e, CatMode.atBazar), isNotNull);
      e.setCustomPlaces([pin, _pin('mosque', id: 'p2', east: 500)]);
      expect(e.evaluate(_t0.add(const Duration(seconds: 401))).mode, CatMode.atBazar);
    });

  });

  group('scenes', () {
    for (final id in CatDirector.placeScenes) {
      test('$id is finite and never jumps', () {
        Pose? last;
        for (var i = 0; i <= 120 * 30; i++) {
          final t = i / 30;
          final p = sampleClip(id, t, ClipCtx(time: t));
          for (final k in P.values) {
            expect(p[k].isFinite, isTrue, reason: '$id $k at $t');
          }
          if (last != null && t > 1.0) {
            // Body parts move smoothly between frames (no pops).
            for (final k in [P.headX, P.headY, P.bodyY, P.rootX, P.rootY, P.fnA1, P.fnA2]) {
              expect((p[k] - last[k]).abs(), lessThan(k == P.fnA1 || k == P.fnA2 ? 0.6 : 3.2),
                  reason: '$id $k at $t');
            }
          }
          last = p;
        }
      });
    }

    test('arriving and leaving have transitions', () {
      expect(CatDirector.plan(ClipId.walk, CatMode.atBazar), [ClipId.bazar]);
      expect(CatDirector.plan(ClipId.park, CatMode.walking), [ClipId.leavePlace, ClipId.walk]);
      expect(CatDirector.plan(ClipId.feast, CatMode.fast), [ClipId.leavePlace, ClipId.fast]);
    });

    test('a tap gets a boop and the scene carries on', () {
      final d = CatDirector()..snapTo(CatMode.atBusStop);
      d.update(2);
      expect(d.tap(), isTrue);
      d.update(0.5);
      expect(d.clip, ClipId.busWait);
    });

    test('the director stays at full frame rate while the bus passes', () {
      final d = CatDirector()..snapTo(CatMode.atBusStop);
      var calmDuringBus = false, calmWaiting = false;
      for (var i = 0; i < 16 * 30; i++) {
        d.update(1 / 30);
        final bus = d.pose[P.busX] > 0.001 && d.pose[P.busX] < 0.999;
        if (bus && d.calm) calmDuringBus = true;
        if (!bus && d.time > 2 && d.time < 6 && d.calm) calmWaiting = true;
      }
      expect(calmDuringBus, isFalse);
      expect(calmWaiting, isTrue);
    });

    test('new words for the speech bubble exist', () {
      expect(homeSayings.length, greaterThanOrEqualTo(12));
    });
  });
}
