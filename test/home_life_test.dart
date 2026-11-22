import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_director.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/tracking/activity_engine.dart';

void main() {
  test('night means sleep', () {
    expect(CatDirector.homeActivityAt(DateTime(2026, 11, 22, 23, 30)), ClipId.sleep);
    expect(CatDirector.homeActivityAt(DateTime(2026, 11, 22, 3, 0)), ClipId.sleep);
  });

  test('daytime activities are shuffled, all appear, never twice in a row', () {
    final seen = <ClipId>{};
    ClipId? prev;
    var start = DateTime(2026, 11, 22, 8);
    for (var m = 0; m < 14 * 60; m++) {
      final a = CatDirector.homeActivityAt(start.add(Duration(minutes: m)));
      expect(a, isNot(prev), reason: 'minute $m repeats $a');
      seen.add(a);
      prev = a;
    }
    expect(seen, containsAll(CatDirector.homeActivities));
  });

  test('order is not the same fixed sequence every block', () {
    String block(int b) => List.generate(6, (i) =>
        CatDirector.homeActivityAt(DateTime(2026, 11, 22, 9).add(Duration(minutes: b * 6 + i))).name).join(',');
    expect({block(0), block(1), block(2), block(3)}.length, greaterThan(1));
  });

  test('plans between home activities', () {
    expect(CatDirector.plan(ClipId.sleep, CatMode.atHome, home: ClipId.eat), [ClipId.homeWake, ClipId.eat]);
    expect(CatDirector.plan(ClipId.eat, CatMode.atHome, home: ClipId.sleep), [ClipId.homeStroll, ClipId.tuckInHome, ClipId.sleep]);
    expect(CatDirector.plan(ClipId.gaming, CatMode.walking).first, ClipId.leaveHome);
  });

  test('director moves on to the next activity when the minute changes', () {
    var now = DateTime(2026, 11, 22, 10, 0, 1);
    final d = CatDirector(clock: () => now)..snapTo(CatMode.atHome);
    final first = d.clip;
    for (var i = 0; i < 40; i++) {
      d.update(1);
      now = now.add(const Duration(seconds: 1));
    }
    now = now.add(const Duration(minutes: 1));
    for (var i = 0; i < 20; i++) {
      d.update(0.5);
    }
    expect(d.clip, isNot(first));
    expect(d.label, homeLabel);
  });
}
