import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/clips.dart';

/// Paints every clip at several moments into one sheet. Doubles as a smoke
/// test (no clip may throw) and as a visual review aid: build/contact_sheet.png
void main() {
  test('every clip paints at every moment (and writes a contact sheet)', () async {
    const cell = 210.0;
    final samples = <(ClipId, double)>[];
    for (final id in ClipId.values) {
      final d = clipSpecs[id]!.duration ?? 6.0;
      for (var i = 0; i < 6; i++) {
        samples.add((id, d * i / 5.0 * 0.999));
      }
    }
    const cols = 6;
    final rows = ClipId.values.length;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, cols * cell, 2000 * 10),
        Paint()..color = const Color(0xFFF4EFE6));
    final h = cell * CatCanvas.height / CatCanvas.width;
    for (var i = 0; i < samples.length; i++) {
      final (id, t) = samples[i];
      final pose = sampleClip(id, t, ClipCtx(time: t));
      canvas.save();
      canvas.translate((i % cols) * cell, (i ~/ cols) * h);
      CatPainter(pose).paint(canvas, Size(cell, h));
      canvas.restore();
    }
    // Also small (real marker size) renders of a few key poses on the last row.
    final pic = recorder.endRecording();
    final img = await pic.toImage((cols * cell).toInt(), (rows * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/contact_sheet.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(out.existsSync(), isTrue);
  });
}
