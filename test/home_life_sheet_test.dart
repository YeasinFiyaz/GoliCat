import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/clips.dart';

/// Large render of the home-life clips for visual review: build/home_sheet.png
void main() {
  test('home-life clips render large', () async {
    const cell = 300.0;
    final h = cell * CatCanvas.height / CatCanvas.width;
    const rows = <(ClipId, List<double>)>[
      (ClipId.bath, [0.4, 1.3, 2.6, 3.0, 3.9, 5.6, 8.6]),
      (ClipId.eat, [0.5, 1.6, 2.0, 3.5, 15.0, 28.0, 59.0]),
      (ClipId.potty, [0.5, 2.5, 6.0, 7.9, 8.8, 9.5, 12.0]),
      (ClipId.lounge, [0.5, 2.0, 6.5, 6.8, 14.0, 16.5, 17.0]),
      (ClipId.gaming, [0.6, 2.0, 4.0, 7.4, 8.0, 17.6, 18.4]),
      (ClipId.homeStroll, [0.1, 0.4, 0.7, 1.0, 1.15, 1.4, 1.6]),
      (ClipId.leaveHome, [0.1, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3]),
    ];
    const cols = 7;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, rows.length * h), Paint()..color = const Color(0xFFF4EFE6));
    for (var r = 0; r < rows.length; r++) {
      final (id, times) = rows[r];
      for (var col = 0; col < cols; col++) {
        final t = times[col];
        canvas.save();
        canvas.translate(col * cell, r * h);
        CatPainter(sampleClip(id, t, ClipCtx(time: t))).paint(canvas, Size(cell, h));
        canvas.restore();
      }
    }
    final img = await recorder.endRecording().toImage((cols * cell).toInt(), (rows.length * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/home_sheet.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
