import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/cat/cat_painter.dart';
import 'package:golicat/cat/clips.dart';

/// Renders transparent cat pictures for the download page: share/site/get/img/*.png
void main() {
  test('download-page art', () async {
    final picks = {'walk': (ClipId.walk, 0.3), 'tea': (ClipId.tea, 2.0), 'typing': (ClipId.typing, 1.2)};
    for (final e in picks.entries) {
      final (id, t) = e.value;
      final img = await renderPose(sampleClip(id, t, ClipCtx(time: t)), 560);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('share/site/get/img/${e.key}.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
