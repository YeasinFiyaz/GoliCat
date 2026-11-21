import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/cat_skin.dart';
import 'package:golicat/cat/clips.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/place_store.dart';
import 'package:golicat/share/share_state.dart';
import 'package:golicat/tracking/activity_engine.dart';
import 'package:golicat/ui/avatar_screen.dart';
import 'package:golicat/ui/theme.dart';
import 'package:golicat/viewer/viewer_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'seeded': true});
    activeCatSkin.value = CatSkin.original;
  });

  test('17 avatars with unique ids, safe to send to the share server', () {
    final ids = CatSkin.all.map((s) => s.id).toList();
    expect(ids.length, 17);
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(RegExp(r'^[a-z]{1,24}$').hasMatch(id), isTrue, reason: id);
    }
    expect(CatSkin.all.where((s) => s.isHero).map((s) => s.name),
        ['Batcat', 'Supermancat', 'Spidercat', 'Catwoman', 'Ironmancat', 'Wonderwomancat']);
    expect(CatSkin.byId('nope').id, 'goli');
    expect(CatSkin.byId(null).id, 'goli');
  });

  test('every avatar paints every clip (and writes build/avatars.png)', () async {
    const cell = 180.0;
    final h = cell * CatCanvas.height / CatCanvas.width;
    final clips = [ClipId.idle, ClipId.walk, ClipId.fast, ClipId.tea, ClipId.typing, ClipId.sleep];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, clips.length * cell, CatSkin.all.length * h),
        Paint()..color = const Color(0xFFF4EFE6));
    for (var r = 0; r < CatSkin.all.length; r++) {
      // Smoke: no clip may throw for any avatar.
      for (final id in ClipId.values) {
        final d = clipSpecs[id]!.duration ?? 6.0;
        CatPainter(sampleClip(id, d * 0.5, ClipCtx(time: d * 0.5)), skin: CatSkin.all[r])
            .paint(Canvas(ui.PictureRecorder()), Size(cell, h));
      }
      for (var col = 0; col < clips.length; col++) {
        canvas.save();
        canvas.translate(col * cell, r * h);
        CatPainter(sampleClip(clips[col], 1.2, const ClipCtx(time: 1.2)), skin: CatSkin.all[r])
            .paint(canvas, Size(cell, h));
        canvas.restore();
      }
    }
    final img = await recorder
        .endRecording()
        .toImage((clips.length * cell).toInt(), (CatSkin.all.length * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/avatars.png')..parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(out.existsSync(), isTrue);
  });

  test('the chosen avatar is saved and restored', () async {
    final store = await AppStore.load();
    expect(store.catSkinId, 'goli');
    store.catSkinId = 'batcat';
    expect(activeCatSkin.value.id, 'batcat');

    activeCatSkin.value = CatSkin.original;
    final again = await AppStore.load();
    expect(again.catSkinId, 'batcat');
    expect(activeCatSkin.value.id, 'batcat');
  });

  test('a live share viewer shows the sharer\'s avatar', () {
    final now = DateTime(2026, 11, 21, 17);
    final st = ShareState.fromJson({'lat': 23.78, 'lng': 90.39, 'mode': 'walking', 'skin': 'spidercat'})!;
    expect(st.skin, 'spidercat');
    ViewerSession(clock: () => now).apply(st);
    expect(activeCatSkin.value.id, 'spidercat');

    // Older apps send no avatar: the original cat.
    ViewerSession(clock: () => now)
        .apply(ShareState(point: const GeoPoint(23.78, 90.39), mode: CatMode.idle, at: now));
    expect(activeCatSkin.value.id, 'goli');
  });

  testWidgets('picker: tapping a cat selects it everywhere', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = await AppStore.load();
    await tester.pumpWidget(MaterialApp(theme: GoliTheme.light(), home: AvatarScreen(store: store)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Choose your cat'), findsOneWidget);
    expect(find.text('Goli'), findsNWidgets(2)); // preview + tile

    await tester.tap(find.byKey(const ValueKey('avatar_ginger')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.catSkinId, 'ginger');
    expect(activeCatSkin.value.name, 'Komola');
    expect(find.text('Komola'), findsNWidgets(2));

    await tester.scrollUntilVisible(find.byKey(const ValueKey('avatar_wonderwomancat')), 200);
    await tester.ensureVisible(find.byKey(const ValueKey('avatar_wonderwomancat')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('avatar_wonderwomancat')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.catSkinId, 'wonderwomancat');
    await tester.pumpWidget(const SizedBox());
  });
}
