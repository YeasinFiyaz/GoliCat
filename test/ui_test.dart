import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/places/place_store.dart';
import 'package:golicat/tracking/trip_recorder.dart';
import 'package:golicat/ui/comic_screen.dart';
import 'package:golicat/ui/demo_screen.dart';
import 'package:golicat/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _shot(WidgetTester tester, String name) async {
  final ro = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image img = await ro.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'seeded': true}));

  testWidgets('demo: jump to At work, play, tap for the fish gag, jump home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = await AppStore.load();
    await tester.pumpWidget(MaterialApp(theme: GoliTheme.light(), home: DemoScreen(store: store)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('DEMO MAP'), findsOneWidget);

    await tester.tap(find.text('At work ⌨'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('At work'), findsWidgets);
    await _shot(tester, 'demo_at_work');

    // Tap the cat (centre of the demo camera) → fish gag.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, (size.height - 230) / 2 + 20 - 30));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('fish'), findsOneWidget);

    await tester.ensureVisible(find.text('Home 💤'));
    await tester.pump();
    await tester.tap(find.text('Home 💤'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Asleep'), findsOneWidget);
    await _shot(tester, 'demo_home');

    await tester.ensureVisible(find.text('Cha break'));
    await tester.pump();
    await tester.tap(find.text('Cha break'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Cha'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('comic renders three panels without coordinates', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final t0 = DateTime(2026, 11, 21, 9);
    final log = TripLog(startedAt: t0);
    for (final (c, s) in [(ClipId.walk, 0), (ClipId.tea, 100), (ClipId.walk, 400), (ClipId.typing, 900)]) {
      log.addClip(c, t0.add(Duration(seconds: s)));
    }
    log.endedAt = t0.add(const Duration(minutes: 20));
    log.distanceM = 1340;
    await tester.pumpWidget(MaterialApp(theme: GoliTheme.light(), home: ComicScreen(log: log)));
    await tester.pump();
    expect(find.text('Off we go'), findsOneWidget);
    expect(find.text('The best bit'), findsOneWidget);
    expect(find.textContaining('1.3 km'), findsOneWidget);
    await _shot(tester, 'comic');
  });
}
