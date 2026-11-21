import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/tracking/trip_recorder.dart';
import 'package:golicat/ui/comic_screen.dart';
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
