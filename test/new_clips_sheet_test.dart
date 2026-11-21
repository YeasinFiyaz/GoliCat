import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/clips.dart';

/// Large render of the study and hangout clips for visual review: build/places_sheet.png
void main() {
  test('study + hangout clips render large', () async {
    const cell = 320.0;
    final h = cell * CatCanvas.height / CatCanvas.width;
    const ids = [
      ClipId.sitAtDesk, ClipId.study, ClipId.stuckGag, ClipId.closeBook,
      ClipId.headphonesOn, ClipId.vibe, ClipId.danceGag, ClipId.headphonesOff,
    ];
    const cols = 6;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, ids.length * h), Paint()..color = const Color(0xFFF4EFE6));
    for (var r = 0; r < ids.length; r++) {
      final d = clipSpecs[ids[r]]!.duration ?? 11.0;
      for (var col = 0; col < cols; col++) {
        final t = d * col / (cols - 1) * 0.999;
        canvas.save();
        canvas.translate(col * cell, r * h);
        CatPainter(sampleClip(ids[r], t, ClipCtx(time: t))).paint(canvas, Size(cell, h));
        canvas.restore();
      }
    }
    final img = await recorder.endRecording().toImage((cols * cell).toInt(), (ids.length * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/places_sheet.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
