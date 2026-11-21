import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../cat/cat_layer.dart';
import '../core/geo.dart';
import 'demo_script.dart';

/// Camera over the illustrated demo map (metres, north up).
class DemoProjector implements MapProjector {
  double camE = 0, camN = 0;
  double pxPerM = 1.25;
  Size size = Size.zero;
  double bottomInset = 0;

  Offset get center => Offset(size.width / 2, (size.height - bottomInset) / 2 + 20);

  @override
  double get bearingDeg => 0;

  Offset localToScreen(double e, double n) => center + Offset((e - camE) * pxPerM, -(n - camN) * pxPerM);

  @override
  Offset? toScreen(GeoPoint p) {
    if (size.isEmpty) return null;
    final l = toLocalM(DemoScript.origin, p);
    return localToScreen(l.east, l.north);
  }

  void follow(GeoPoint p, double dt) {
    final l = toLocalM(DemoScript.origin, p);
    final k = 1 - math.exp(-dt * 2.5);
    camE += (l.east - camE) * k;
    camN += (l.north - camN) * k;
  }

  void snap(GeoPoint p) {
    final l = toLocalM(DemoScript.origin, p);
    camE = l.east;
    camN = l.north;
  }
}

/// Hand-drawn style backdrop: obviously illustrated, labelled DEMO MAP.
class DemoMapPainter extends CustomPainter {
  DemoMapPainter(this.cam, {super.repaint});
  final DemoProjector cam;

  static const _ground = Color(0xFFF1E9DA);
  static const _road = Color(0xFFFFFFFF);
  static const _roadEdge = Color(0xFFD9CDB8);
  static const _block = Color(0xFFE3D5BE);
  static const _blockEdge = Color(0xFFC9B79A);
  static const _ink = Color(0xFF5A4A3C);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _ground);
    Offset s(double e, double n) => cam.localToScreen(e, n);
    final k = cam.pxPerM;

    // Blocks of buildings (deterministic).
    final bp = Paint()..color = _block;
    final be = Paint()
      ..color = _blockEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var bx = -400; bx < 1300; bx += 46) {
      for (final side in [-1, 1]) {
        for (var row = 0; row < 4; row++) {
          final seed = bx * 7 + side * 13 + row * 31;
          final w = 26 + (seed % 9) * 1.5, h = 18 + (seed % 7) * 2.0;
          final n0 = side * (14 + row * 34.0);
          if ((bx - 540).abs() < 70 && side == 1 && row < 3) continue; // office plot
          if ((bx - 850).abs() < 40 && side == -1) continue; // Bari Goli
          if ((bx - 250).abs() < 25 || (bx - 700).abs() < 25) continue; // cross lanes
          final r = Rect.fromPoints(s(bx.toDouble(), n0), s(bx + w, n0 + side * h));
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), bp);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), be);
        }
      }
    }

    void road(double e0, double n0, double e1, double n1, double width) {
      final edge = Paint()
        ..color = _roadEdge
        ..strokeWidth = (width + 3) * k
        ..strokeCap = StrokeCap.round;
      final fill = Paint()
        ..color = _road
        ..strokeWidth = width * k
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(s(e0, n0), s(e1, n1), edge);
      canvas.drawLine(s(e0, n0), s(e1, n1), fill);
    }

    road(-500, 0, 1400, 0, 14);
    road(540, 0, 540, 150, 7);
    road(850, 0, 850, -300, 7);
    road(250, -200, 250, 200, 7);
    road(700, -200, 700, 200, 7);

    // Office and home circles.
    void ring(Offset2 c, double r, Color col) {
      canvas.drawCircle(s(c.x, c.y), r * k, Paint()..color = col.withValues(alpha: 0.08));
      canvas.drawCircle(
          s(c.x, c.y),
          r * k,
          Paint()
            ..color = col.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    ring(DemoScript.officeLocal, DemoScript.office.radiusM, const Color(0xFFD7263D));
    ring(DemoScript.homeLocal, DemoScript.home.radiusM, const Color(0xFF2F5D8A));

    // Landmarks.
    void building(Rect r, Color c, String label) {
      final rr = Rect.fromPoints(s(r.left, r.top), s(r.right, r.bottom));
      canvas.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(4)), Paint()..color = c);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rr, const Radius.circular(4)),
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
      _label(canvas, label, rr.center, 12, bold: true);
    }

    building(const Rect.fromLTRB(500, 90, 585, 55), const Color(0xFFF4C7C3), 'Office');
    building(const Rect.fromLTRB(825, -165, 880, -205), const Color(0xFFC9DAEE), 'Home');
    // Cha stall with a striped awning.
    final cha = s(DemoScript.chaLocal.x, 9);
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(Rect.fromLTWH(cha.dx - 15 + i * 6, cha.dy - 14, 6, 7),
          Paint()..color = i.isEven ? const Color(0xFFD7263D) : const Color(0xFFFFFFFF));
    }
    canvas.drawRect(Rect.fromLTWH(cha.dx - 13, cha.dy - 7, 26, 9), Paint()..color = const Color(0xFF9A6A43));
    _label(canvas, 'Cha stall', cha + const Offset(0, -24), 11, bold: true);

    // Street names.
    for (var e = -300.0; e < 1300; e += 330) {
      _label(canvas, 'Cha Stall Road', s(e, 0), 11);
    }
    _label(canvas, 'Office Para Lane', s(540, 125), 10, rotate: -math.pi / 2);
    _label(canvas, 'Bari Goli', s(850, -90), 10, rotate: -math.pi / 2);
    _label(canvas, 'Rickshaw Lane', s(250, 120), 10, rotate: -math.pi / 2);
  }

  void _label(Canvas c, String text, Offset at, double size, {bool bold = false, double rotate = 0}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: _ink,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.3,
          )),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(rotate);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(DemoMapPainter old) => true;
}
