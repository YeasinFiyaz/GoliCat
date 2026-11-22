import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_director.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/cat/pose.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/core/position_glide.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/ui/theme.dart';
import 'package:golicat/update/update_dialog.dart';
import 'package:golicat/update/updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('calm only when settled: never while walking, changing pose or poked', () {
    final night = DateTime(2026, 11, 22, 2);
    final d = CatDirector(clock: () => night)..snapTo(CatMode.atHome);
    expect(d.clip, ClipId.sleep);
    for (var i = 0; i < 30; i++) {
      d.update(0.1);
    }
    expect(d.calm, isTrue, reason: 'asleep');
    d.setMode(CatMode.walking);
    d.update(0.1);
    expect(d.calm, isFalse, reason: 'waking up');
    for (var i = 0; i < 80; i++) {
      d.update(0.1);
    }
    expect(d.clip, ClipId.walk);
    expect(d.calm, isFalse, reason: 'walking');
    d.setMode(CatMode.waiting);
    for (var i = 0; i < 20; i++) {
      d.update(0.1);
      if (d.clip != ClipId.tea) expect(d.calm, isFalse, reason: 'sitting down');
    }
    for (var i = 0; i < 40; i++) {
      d.update(0.1);
    }
    expect(d.clip, ClipId.tea);
    expect(d.calm, isTrue, reason: 'sipping cha');
  });

  test('every polished clip stays finite and on the canvas', () {
    for (final id in [ClipId.fast, ClipId.walk, ClipId.sitDown, ClipId.tea]) {
      for (var t = 0.0; t < 30; t += 0.05) {
        final p = sampleClip(id, t, ClipCtx(time: t));
        for (final v in p.v) {
          expect(v.isFinite, isTrue, reason: '$id at $t');
        }
      }
    }
  });

  test('running loops seamlessly (no jump where the cycle restarts)', () {
    const period = 1 / 3.1;
    final a = sampleClip(ClipId.fast, period - 0.0005, const ClipCtx(time: 5));
    final b = sampleClip(ClipId.fast, period + 0.0005, const ClipCtx(time: 5));
    for (var i = 0; i < a.v.length; i++) {
      expect((a.v[i] - b.v[i]).abs(), lessThan(0.2), reason: 'param $i');
    }
  });

  test('sit down ends exactly where the cha break begins', () {
    final end = sampleClip(ClipId.sitDown, 1.4, const ClipCtx(time: 3));
    final start = sampleClip(ClipId.tea, 0, const ClipCtx(time: 3));
    for (final k in [P.bodyY, P.bodyRot, P.headX, P.headY, P.fnA1, P.fnA2, P.cha, P.tailEndX, P.bnA1]) {
      expect((end[k] - start[k]).abs(), lessThan(0.6), reason: '$k');
    }
  });

  test('glide reports when it is still sliding', () {
    final g = PositionGlide();
    final t0 = DateTime(2026);
    g.target(const GeoPoint(23.7, 90.4), t0);
    expect(g.gliding, isFalse);
    g.target(const GeoPoint(23.7001, 90.4), t0.add(const Duration(seconds: 1)));
    expect(g.gliding, isTrue);
    g.advance(5);
    expect(g.gliding, isFalse);
  });

  group('update popup', () {
    const ch = MethodChannel('golicat/update');
    final apk = List<int>.generate(50000, (i) => i % 251);
    final installed = <String>[];
    late Directory tmp;
    var apkRequests = 0;

    Updater make() => Updater(
          client: MockClient.streaming((req, _) async {
            if (req.url.path.endsWith('.apk')) {
              apkRequests++;
              return http.StreamedResponse(Stream.value(apk), 200);
            }
            return http.StreamedResponse(const Stream.empty(), 404);
          }),
          baseUrl: 'https://example.test',
          tempDir: () async => tmp,
          currentBuild: 1,
        );
    final info = UpdateInfo('9.9.9', 99, {
      'arm64': UpdateFile('golicat-9.9.9-arm64.apk', sha256.convert(apk).toString(), apk.length),
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('golicat_dlg');
      installed.clear();
      apkRequests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'abis':
            return ['arm64-v8a'];
          case 'canInstall':
            return true;
          case 'sha256':
            return sha256.convert(File(call.arguments['path'] as String).readAsBytesSync()).toString();
          case 'install':
            installed.add(call.arguments['path'] as String);
            return true;
        }
        return null;
      });
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> open(WidgetTester tester, Updater u) => tester.pumpWidget(MaterialApp(
          theme: GoliTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => UpdateDialog(updater: u, info: info)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));

    testWidgets('Not now downloads nothing', (tester) async {
      await open(tester, make());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
      expect(find.textContaining('GoliCat 9.9.9'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsNothing);
      expect(apkRequests, 0);
      expect(installed, isEmpty);
    });

    testWidgets('Update downloads, verifies and opens the installer', (tester) async {
      await open(tester, make());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Update'));
        for (var i = 0; i < 40 && installed.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(apkRequests, 1);
      expect(installed.single, endsWith('golicat-9.9.9-arm64.apk'));
      expect(find.text('Install the update'), findsOneWidget);
    });
  });
}
