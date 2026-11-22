import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/clips.dart';

/// Frames of the running, walking and tea-break clips for visual review:
/// build/polish_sheet.png (set POLISH_OUT to change the file name).
void main() {
  test('polish sheet', () async {
    const cell = 260.0;
    final h = cell * CatCanvas.height / CatCanvas.width;
    const cols = 8;
    final rows = <(ClipId, List<double>)>[
      (ClipId.fast, [for (var i = 0; i < cols; i++) i * 0.3 / cols]),
      (ClipId.walk, [for (var i = 0; i < cols; i++) i * 0.476 / cols]),
      (ClipId.sitDown, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4]),
      (ClipId.tea, [0.5, 1.2, 1.8, 2.2, 2.6, 3.2, 3.8, 4.4]),
      (ClipId.tea, [5.5, 6.3, 7.0, 7.6, 8.2, 9.0, 11.0, 13.0]),
    ];
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, rows.length * h), Paint()..color = const Color(0xFFF4EFE6));
    for (var r = 0; r < rows.length; r++) {
      for (var col = 0; col < cols; col++) {
        final t = rows[r].$2[col];
        canvas.save();
        canvas.translate(col * cell, r * h);
        CatPainter(sampleClip(rows[r].$1, t, ClipCtx(time: t))).paint(canvas, Size(cell, h));
        canvas.restore();
      }
    }
    final img = await rec.endRecording().toImage((cols * cell).toInt(), (rows.length * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/${Platform.environment['POLISH_OUT'] ?? 'polish_sheet'}.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
