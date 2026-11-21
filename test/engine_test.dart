import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_director.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/core/geo.dart';
import 'support/demo_script.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/tracking/fix.dart';
import 'package:golicat/tracking/motion_engine.dart';
import 'package:golicat/tracking/place_monitor.dart';
import 'package:golicat/tracking/trip_recorder.dart';

final _t0 = DateTime(2026, 1, 1, 9);
const _o = GeoPoint(23.78, 90.39);

LocationFix fx(double s, double e, double n, {double acc = 8, double speed = -1}) => LocationFix(
    point: offsetM(_o, e, n), time: _t0.add(Duration(milliseconds: (s * 1000).round())), accuracy: acc, speed: speed);

/// Runs the full demo script and returns the mode at every second.
Map<int, CatMode> runScript() {
  final script = DemoScript();
  final eng = ActivityEngine(
      office: DemoScript.office, home: DemoScript.home, education: DemoScript.education, hangout: DemoScript.hangout);
  eng.start(DemoScript.epoch);
  final out = <int, CatMode>{};
  var i = 0;
  for (var s = 0; s <= DemoScript.duration; s++) {
    final now = DemoScript.epoch.add(Duration(seconds: s));
    while (i < script.fixes.length && !script.fixes[i].time.isAfter(now)) {
      eng.addFix(script.fixes[i++]);
    }
    out[s] = eng.evaluate(now).mode;
  }
  return out;
}

void main() {
  group('motion', () {
    test('noisy stationary GPS (incl. one 45 m jump) never starts walking', () {
      final m = MotionEngine();
      final r = math.Random(3);
      for (var s = 0; s < 300; s++) {
        var e = (r.nextDouble() - 0.5) * 14, n = (r.nextDouble() - 0.5) * 14;
        if (s == 120) n += 45;
        m.addFix(fx(s.toDouble(), e, n, acc: 8 + r.nextDouble() * 10, speed: r.nextDouble() * 0.6));
        if (s > 0) expect(m.kind, MotionKind.stationary, reason: 'second $s');
      }
    });

    test('poor-accuracy fixes are ignored entirely', () {
      final m = MotionEngine();
      m.addFix(fx(0, 0, 0));
      for (var s = 1; s < 40; s++) {
        m.addFix(fx(s.toDouble(), s * 20.0, 0, acc: 120));
      }
      expect(m.kind, MotionKind.stationary);
    });

    test('a real walk is detected within ~10 s, a stop within ~25 s', () {
      final m = MotionEngine();
      for (var s = 0; s < 30; s++) {
        m.addFix(fx(s.toDouble(), 0, 0));
      }
      int? movedAt;
      for (var s = 30; s < 90; s++) {
        m.addFix(fx(s.toDouble(), (s - 30) * 1.4, 0, speed: 1.4));
        if (movedAt == null && m.kind == MotionKind.walking) movedAt = s;
      }
      expect(movedAt, isNotNull);
      expect(movedAt! - 30, lessThanOrEqualTo(10));
      int? stoppedAt;
      for (var s = 90; s < 150; s++) {
        m.addFix(fx(s.toDouble(), 84, 0, speed: 0));
        if (stoppedAt == null && m.kind == MotionKind.stationary) stoppedAt = s;
      }
      expect(stoppedAt! - 90, lessThanOrEqualTo(25));
    });

    test('fast travel is recognised from speed alone (no vehicle guessing)', () {
      final m = MotionEngine();
      for (var s = 0; s < 10; s++) {
        m.addFix(fx(s.toDouble(), 0, 0));
      }
      for (var s = 10; s < 40; s++) {
        m.addFix(fx(s.toDouble(), (s - 10) * 8.0, 0, speed: 8));
      }
      expect(m.kind, MotionKind.fast);
    });

    test('goes stale when readings stop', () {
      final m = MotionEngine();
      m.addFix(fx(0, 0, 0));
      expect(m.snapshot(_t0.add(const Duration(seconds: 10))).stale, isFalse);
      expect(m.snapshot(_t0.add(const Duration(seconds: 40))).stale, isTrue);
    });
  });

  group('office', () {
    const office = Place(center: _o, radiusM: 100);

    ActivityEngine eng() => ActivityEngine(office: office)..start(_t0);

    test('walking straight past the office does not clock in', () {
      final e = eng();
      for (var s = 0; s <= 400; s++) {
        e.addFix(fx(s.toDouble(), -280 + s * 1.4, 20, speed: 1.4));
        expect(e.evaluate(_t0.add(Duration(seconds: s))).mode, isNot(CatMode.atWork), reason: 's=$s');
      }
    });

    test('arriving and staying clocks in after about two minutes', () {
      final e = eng();
      int? at;
      for (var s = 0; s <= 400; s++) {
        final east = s < 60 ? -150 + s * 2.5 : 0.0;
        e.addFix(fx(s.toDouble(), east, 0, acc: s < 60 ? 8 : 25));
        if (at == null && e.evaluate(_t0.add(Duration(seconds: s))).mode == CatMode.atWork) at = s;
      }
      expect(at, isNotNull);
      expect(at!, inInclusiveRange(120, 220));
    });

    test('indoor drift near the boundary does not flip-flop', () {
      final e = eng();
      final r = math.Random(11);
      for (var s = 0; s <= 200; s++) {
        e.addFix(fx(s.toDouble(), 0, 0, acc: 15));
        e.evaluate(_t0.add(Duration(seconds: s)));
      }
      expect(e.mode, CatMode.atWork);
      for (var s = 201; s <= 1200; s++) {
        // Drift up to 125 m out (inside the 130 m exit ring), bad fixes far out.
        final far = r.nextDouble() < 0.05;
        final d = far ? 300.0 : r.nextDouble() * 125;
        e.addFix(fx(s.toDouble(), d, 0, acc: far ? 80 : 20 + r.nextDouble() * 25));
        expect(e.evaluate(_t0.add(Duration(seconds: s))).mode, CatMode.atWork, reason: 's=$s');
      }
    });

    test('clearly leaving ends office mode; tea never overrides office', () {
      final e = eng();
      for (var s = 0; s <= 400; s++) {
        e.addFix(fx(s.toDouble(), 0, 0));
        e.evaluate(_t0.add(Duration(seconds: s)));
      }
      expect(e.mode, CatMode.atWork); // still for 400 s but no tea break
      int? leftAt;
      for (var s = 401; s <= 600; s++) {
        e.addFix(fx(s.toDouble(), (s - 400) * 1.5, 0, speed: 1.5));
        if (leftAt == null && e.evaluate(_t0.add(Duration(seconds: s))).mode != CatMode.atWork) leftAt = s;
      }
      expect(leftAt, isNotNull);
      expect((leftAt! - 400) * 1.5, lessThan(200));
    });

    test('losing signal at the office keeps typing', () {
      final e = eng();
      for (var s = 0; s <= 300; s++) {
        e.addFix(fx(s.toDouble(), 0, 0));
      }
      expect(e.evaluate(_t0.add(const Duration(seconds: 300))).mode, CatMode.atWork);
      expect(e.evaluate(_t0.add(const Duration(seconds: 1300))).mode, CatMode.atWork);
    });
  });

  group('signal', () {
    test('losing signal shows the map; a fresh fix resumes', () {
      final e = ActivityEngine()..start(_t0);
      for (var s = 0; s < 20; s++) {
        e.addFix(fx(s.toDouble(), s * 1.4, 0, speed: 1.4));
      }
      expect(e.evaluate(_t0.add(const Duration(seconds: 19))).mode, CatMode.walking);
      expect(e.evaluate(_t0.add(const Duration(seconds: 60))).mode, CatMode.lost);
      e.addFix(fx(61, 40, 0, speed: 1.4));
      expect(e.evaluate(_t0.add(const Duration(seconds: 61))).mode, isNot(CatMode.lost));
    });

    test('no network: coarse fixes are followed once good ones dry up', () {
      final e = ActivityEngine()..start(_t0);
      for (var s = 0; s < 20; s++) {
        e.addFix(fx(s.toDouble(), s * 1.4, 0, speed: 1.4));
      }
      // Assisted GPS gone: every fix is 60 m. Ignored at first…
      for (var s = 20; s < 40; s++) {
        e.addFix(fx(s.toDouble(), s * 1.4, 0, speed: 1.4, acc: 60));
      }
      final frozen = e.evaluate(_t0.add(const Duration(seconds: 39)));
      expect(frozen.position!.lng, closeTo(e.evaluate(_t0.add(const Duration(seconds: 19))).position!.lng, 1e-9));
      // …but after staleAfter the coarse track is used, so the cat keeps going.
      for (var s = 40; s < 90; s++) {
        e.addFix(fx(s.toDouble(), s * 1.4, 0, speed: 1.4, acc: 60));
      }
      final later = e.evaluate(_t0.add(const Duration(seconds: 89)));
      expect(later.mode, isNot(CatMode.lost));
      expect(later.position!.lng, greaterThan(frozen.position!.lng + 0.0001));
      // Junk (120 m) is still never followed.
      expect(e.motion.addFix(fx(90, 500, 0, acc: 120)), isFalse);
    });

    test('tea break starts after a minute of stillness', () {
      final e = ActivityEngine()..start(_t0);
      for (var s = 0; s < 100; s++) {
        e.addFix(fx(s.toDouble(), 0, 0));
        final m = e.evaluate(_t0.add(Duration(seconds: s))).mode;
        if (s < 55) expect(m, CatMode.idle);
        if (s > 65) expect(m, CatMode.waiting);
      }
    });
  });

  group('full demo script', () {
    final modes = runScript();
    bool any(int a, int b, CatMode m) => [for (var s = a; s <= b; s++) modes[s]].contains(m);
    bool all(int a, int b, CatMode m) => [for (var s = a; s <= b; s++) modes[s]].every((x) => x == m);

    test('walks, then cha, ignoring the 45 m jump', () {
      expect(all(15, 60, CatMode.walking), isTrue);
      expect(all(160, 200, CatMode.waiting), isTrue, reason: '${[for (var s = 140; s <= 205; s++) modes[s]!.name]}');
    });
    test('fast ride, then walking past the office without clocking in', () {
      expect(any(270, 300, CatMode.fast), isTrue);
      expect(any(312, 470, CatMode.atWork), isFalse);
      expect(any(330, 460, CatMode.walking), isTrue);
    });
    test('signal loss shows the paper map', () {
      expect(any(495, 520, CatMode.lost), isTrue);
    });
    test('arrives at work and stays through indoor drift', () {
      final first = [for (var s = 600; s <= 900; s++) if (modes[s] == CatMode.atWork) s].first;
      expect(first, lessThan(760));
      expect(all(first, 930, CatMode.atWork), isTrue);
    });
    test('leaves the office, hangs out, studies, then sleeps at home', () {
      expect(any(1025, 1060, CatMode.atWork), isFalse);
      expect(any(1075, 1300, CatMode.hangingOut), isTrue);
      expect(all(1240, 1300, CatMode.hangingOut), isTrue, reason: '${[for (var s = 1200; s <= 1300; s += 10) modes[s]!.name]}');
      expect(any(1400, 1650, CatMode.studying), isTrue);
      expect(all(1580, 1650, CatMode.studying), isTrue, reason: '${[for (var s = 1500; s <= 1650; s += 10) modes[s]!.name]}');
      // Leaving needs the wider exit ring (hysteresis), so a few seconds after 1700.
      expect(any(1735, 1950, CatMode.studying), isFalse);
      expect(all(1880, 1950, CatMode.atHome), isTrue); // home at 1740 + 2 min dwell
    });
  });

  group('director', () {
    test('tea → moving plays stash-the-glass then catch-up', () {
      expect(CatDirector.plan(ClipId.tea, CatMode.walking), [ClipId.stashTea, ClipId.catchUp, ClipId.walk]);
      expect(CatDirector.plan(ClipId.fast, CatMode.walking), [ClipId.skid, ClipId.walk]);
      expect(CatDirector.plan(ClipId.walk, CatMode.atWork), [ClipId.hopOnChair, ClipId.typing]);
      expect(CatDirector.plan(ClipId.typing, CatMode.walking), [ClipId.leaveOffice, ClipId.walk]);
      expect(CatDirector.plan(ClipId.sleep, CatMode.walking), [ClipId.wakeUp, ClipId.walk]);
      expect(CatDirector.plan(ClipId.walk, CatMode.studying), [ClipId.sitAtDesk, ClipId.study]);
      expect(CatDirector.plan(ClipId.study, CatMode.walking), [ClipId.closeBook, ClipId.walk]);
      expect(CatDirector.plan(ClipId.walk, CatMode.hangingOut), [ClipId.headphonesOn, ClipId.vibe]);
      expect(CatDirector.plan(ClipId.vibe, CatMode.atHome), [ClipId.headphonesOff, ClipId.tuckIn, ClipId.sleep]);
    });

    test('mode changes play through visibly and settle into the right loop', () {
      final d = CatDirector();
      d.setMode(CatMode.waiting);
      for (var i = 0; i < 200; i++) {
        d.update(1 / 60);
      }
      expect(d.clip, ClipId.tea);
      d.setMode(CatMode.walking);
      expect(d.clip, ClipId.stashTea);
      for (var i = 0; i < 300; i++) {
        d.update(1 / 60);
      }
      expect(d.clip, ClipId.walk);
      expect(d.history, containsAllInOrder([ClipId.sitDown, ClipId.tea, ClipId.stashTea, ClipId.catchUp, ClipId.walk]));
    });

    test('taps: bat the pin when still, fish gag at work', () {
      final d = CatDirector();
      d.update(0.1);
      expect(d.tap(), isTrue);
      expect(d.clip, ClipId.batPin);
      d.snapTo(CatMode.atWork);
      expect(d.tap(), isTrue);
      expect(d.clip, ClipId.fishGag);
      for (var i = 0; i < 300; i++) {
        d.update(1 / 60);
      }
      expect(d.clip, ClipId.typing);
    });
  });

  group('comic', () {
    test('walk → cha → work gives trot, cha, Enter', () {
      final log = TripLog(startedAt: _t0);
      for (final (c, s) in [(ClipId.walk, 0), (ClipId.sitDown, 100), (ClipId.tea, 102), (ClipId.stashTea, 400), (ClipId.walk, 401), (ClipId.hopOnChair, 900), (ClipId.typing, 902)]) {
        log.addClip(c, _t0.add(Duration(seconds: s)));
      }
      log.endedAt = _t0.add(const Duration(seconds: 1200));
      final panels = comicFor(log);
      expect(panels.map((p) => p.clip), [ClipId.walk, ClipId.tea, ClipId.typing]);
      expect(panels[1].caption, contains('4-minute'));
    });
    test('a short trip with no pause is still honest', () {
      final log = TripLog(startedAt: _t0)..addClip(ClipId.walk, _t0);
      log.endedAt = _t0.add(const Duration(minutes: 3));
      final panels = comicFor(log);
      expect(panels[1].caption, contains('No stops'));
    });
    test('journal stores no coordinates', () {
      final log = TripLog(startedAt: _t0)..addClip(ClipId.walk, _t0);
      final json = log.toJson();
      expect(json.contains('lat'), isFalse);
      expect(json.contains('23.'), isFalse);
    });
  });
}
