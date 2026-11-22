import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/cat_skin.dart';
import 'package:golicat/cat/clips.dart';

typedef _Cell = (ClipId, double, CatSkin?);

/// Large render of the "More places" scenes for visual review:
/// build/place_sheet.png (original cat) and build/place_sheet_skins.png (every avatar).
void main() {
  Future<void> sheet(String file, List<List<_Cell>> rows) async {
    const cell = 300.0;
    final h = cell * CatCanvas.height / CatCanvas.width;
    final cols = rows.first.length;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, rows.length * h), Paint()..color = const Color(0xFFF4EFE6));
    for (var r = 0; r < rows.length; r++) {
      for (var col = 0; col < cols; col++) {
        final (id, t, skin) = rows[r][col];
        canvas.save();
        canvas.translate(col * cell, r * h);
        CatPainter(sampleClip(id, t, ClipCtx(time: t)), skin: skin).paint(canvas, Size(cell, h));
        canvas.restore();
      }
    }
    final img = await recorder.endRecording().toImage((cols * cell).toInt(), (rows.length * h).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File(file)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  List<_Cell> row(ClipId id, List<double> times) => [for (final t in times) (id, t, null)];

  test('place scenes render large', () async {
    await sheet('build/place_sheet.png', [
      row(ClipId.bazar, [0.3, 1.2, 3.0, 4.3, 6.0, 8.2, 11.0]),
      row(ClipId.feast, [0.4, 1.6, 2.0, 30.0, 41.5, 44.0, 47.0]),
      row(ClipId.busWait, [0.5, 2.0, 4.8, 6.5, 7.6, 8.2, 10.0]),
      row(ClipId.busWait, [12.5, 15.2, 16.5, 7.0, 8.8, 9.0, 13.5]),
      row(ClipId.park, [0.8, 4.3, 5.5, 6.3, 9.5, 15.0, 16.8]),
      row(ClipId.park, [17.3, 17.8, 13.1, 19.5, 7.6, 2.0, 18.3]),
      row(ClipId.leavePlace, [0.1, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3]),
    ]);
    await sheet('build/place_sheet_skins.png', [
      for (final s in CatSkin.all)
        [(ClipId.bazar, 11.0, s), (ClipId.feast, 3.0, s), (ClipId.busWait, 10.0, s), (ClipId.park, 16.8, s)],
    ]);
  });
}
