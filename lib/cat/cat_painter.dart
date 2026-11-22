import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'cat_skin.dart';
import 'pose.dart';

/// GoliCat's palette.
class CatInk {
  static const ink = Color(0xFF4A2A20);
  static const fur = Color(0xFFFFFFFF);
  static const furFar = Color(0xFFEDE4D8);
  static const stripe = Color(0xFFF2A65A); // orange patches
  static const cream = Color(0xFFFBEFD9);
  static const earPink = Color(0xFFF7B6A8);
  static const blush = Color(0xFFF7A6A0);
  static const nose = Color(0xFFE08A8A);
  static const scarf = Color(0xFFD7263D);
  static const scarfDark = Color(0xFF9C1A2D);
  static const tea = Color(0xFFC0702A);
  static const glass = Color(0xCCE8F1F4);
  static const paper = Color(0xFFF0E4C4);
  static const wood = Color(0xFF9A6A43);
  static const metal = Color(0xFF6F7A83);
  static const screen = Color(0xFF223440);
  static const screenText = Color(0xFF9BE3A8);
  static const kantha = Color(0xFF2F5D8A);
  static const kanthaStitch = Color(0xFFF7E8C8);
  static const pillow = Color(0xFFF5F1E8);
}

/// Canvas geometry in cat units: 140 wide, origin 70 from the left and 88
/// from the top, so the cat's feet sit on the anchor point.
class CatCanvas {
  static const double width = 140;
  static const double height = 100;
  static const double originX = 70;
  static const double originY = 88;
}

/// Paints one [Pose]. Pure drawing: no timing, no state.
class CatPainter extends CustomPainter {
  CatPainter(this.pose, {this.boil = 0, this.reducedMotion = false, this.skin, super.repaint});

  final Pose pose;

  /// Avatar to draw; defaults to the one the user picked.
  final CatSkin? skin;

  /// Changes a few times a second to make lines "boil" like hand animation.
  final int boil;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / CatCanvas.width;
    canvas.save();
    canvas.scale(s);
    canvas.translate(CatCanvas.originX, CatCanvas.originY);
    _CatDraw(canvas, pose, reducedMotion ? 0 : boil, skin ?? activeCatSkin.value).draw();
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatPainter old) => true;
}

class _CatDraw {
  _CatDraw(this.c, this.p, this.boil, this.k);

  /// The avatar colours.
  final CatSkin k;
  final Canvas c;
  final Pose p;
  final int boil;
  int _seed = 0;

  static const double inkW = 1.7;
  Paint get _ink => Paint()
    ..color = k.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = inkW
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  Paint _fill(Color col, [double alpha = 1]) => Paint()
    ..color = col.withValues(alpha: col.a * alpha.clamp(0.0, 1.0))
    ..style = PaintingStyle.fill;

  double get facing => p[P.facing];

  // -------------------------------------------------------------------------
  void draw() {
    final office = p[P.office].clamp(0.0, 1.0);
    final home = p[P.home].clamp(0.0, 1.0);

    _shadow();
    if (p[P.pinVis] > 0.01) _pin(p[P.pinVis] * (1 - office) * (1 - home));
    if (p[P.speedLines] > 0.01) _speedLines();
    if (p[P.dust] > 0.01) _dust();

    // Scene flip for facing; marks/text are drawn later un-mirrored.
    c.save();
    final f = facing.abs() < 0.08 ? 0.08 * (facing.isNegative ? -1 : 1) : facing;
    c.scale(f, 1);

    if (home > 0.01) _homeBack(home);
    if (office > 0.01) _officeBack(office);
    if (p[P.bench] > 0.01) _benchBack(p[P.bench]);
    if (p[P.desk] > 0.01) _deskBack(p[P.desk]);
    if (p[P.bucket] > 0.01) _bucket(p[P.bucket]);
    if (p[P.plate] > 0.01) _plate(p[P.plate], p[P.bite]);
    if (p[P.tv] > 0.01) _tv(p[P.tv]);
    if (p[P.litter] > 0.01) _litterBack(p[P.litter]);

    c.save();
    c.translate(p[P.rootX], p[P.rootY]);
    final sq = p[P.squash];
    if (sq != 0) {
      c.scale(1 + sq * 0.6, 1 - sq);
    }

    _leg(P.ffX, P.ffY, P.ffA1, P.ffA2, p[P.legLen], far: true);
    _leg(P.bfX, P.bfY, P.bfA1, P.bfA2, p[P.legLenB], far: true);
    _tail();
    _leg(P.bnX, P.bnY, P.bnA1, P.bnA2, p[P.legLenB]);
    _body();
    if (p[P.blanket] > 0.01) _blanket(p[P.blanket], p[P.blanketHead]);
    _scarfOnNeck();
    _drawHead();
    _scarfBand();
    if (p[P.blanketHead] > 0.01) _blanketOverHead(p[P.blanketHead] * p[P.blanket]);
    c.restore();

    if (office > 0.01) _officeFront(office);
    if (p[P.litter] > 0.01) _litterFront(p[P.litter]);

    c.save();
    c.translate(p[P.rootX], p[P.rootY]);
    if (sq != 0) c.scale(1 + sq * 0.6, 1 - sq);
    if (p[P.mapVis] > 0.01) _paperMap();
    if (p[P.desk] > 0.01) _deskFront(p[P.desk]); // the paws rest on top of it
    if (p[P.blanket] < 0.6) _leg(P.fnX, P.fnY, P.fnA1, P.fnA2, p[P.legLen]);
    if (p[P.pencil] > 0.01) _pencil(p[P.pencil]);
    if (p[P.cha] > 0.01) _chaGlass();
    if (p[P.mug] > 0.01) _mug(p[P.mug]);
    if (p[P.paper] > 0.01) _newspaper(p[P.paper]);
    if (p[P.phone] > 0.01) _phone(p[P.phone]);
    if (p[P.gamepad] > 0.01) _gamepad(p[P.gamepad]);
    if (p[P.foam] > 0.01) _foam(p[P.foam].clamp(0.0, 1.0));
    if (p[P.splash] > 0.01) _splash(p[P.splash]);
    if (p[P.glassesFace] > 0.01) _glassesOnFace(p[P.glassesFace]);
    if (p[P.scarfFace] > 0.01) _scarfOverFace(p[P.scarfFace]);
    if (p[P.bubble] > 0.02) _snotBubble();
    c.restore();
    c.restore();

    _marks();
  }

  // ---- geometry helpers ----------------------------------------------------

  Offset _rot(Offset v, double a) => Offset(
      v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));

  double _n(int i) => hashNoise(boil * 31 + _seed, i);

  /// Closed smooth blob through points with a little hand-drawn jitter.
  Path _blob(List<Offset> pts, {double jitter = 0.35}) {
    _seed++;
    final q = <Offset>[
      for (var i = 0; i < pts.length; i++)
        pts[i] + Offset(_n(i * 2) * jitter, _n(i * 2 + 1) * jitter),
    ];
    final path = Path();
    final n = q.length;
    path.moveTo((q[0].dx + q[1].dx) / 2, (q[0].dy + q[1].dy) / 2);
    for (var i = 1; i <= n; i++) {
      final cur = q[i % n], nxt = q[(i + 1) % n];
      path.quadraticBezierTo(cur.dx, cur.dy, (cur.dx + nxt.dx) / 2, (cur.dy + nxt.dy) / 2);
    }
    path.close();
    return path;
  }

  Path _ellipse(Offset center, double rx, double ry, double rot, {int n = 12, double jitter = 0.35}) {
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        center + _rot(Offset(rx * math.cos(2 * math.pi * i / n), ry * math.sin(2 * math.pi * i / n)), rot),
    ];
    return _blob(pts, jitter: jitter);
  }

  void _shape(Path path, Color fill, [double alpha = 1]) {
    c.drawPath(path, _fill(fill, alpha));
    c.drawPath(path, _ink..color = k.ink.withValues(alpha: alpha.clamp(0.0, 1.0)));
  }

  /// Thick outlined stroke (legs, tail, ribbons).
  void _limb(List<Offset> pts, double width, Color col, {double alpha = 1}) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    c.drawPath(
        path,
        Paint()
          ..color = k.ink.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + inkW * 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    c.drawPath(
        path,
        Paint()
          ..color = col.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  Offset get _head => Offset(p[P.headX], p[P.headY]);

  /// Point on the head in head-local coordinates (rotates with the head).
  Offset _hp(double x, double y) => _head + _rot(Offset(x, y), p[P.headRot]);

  // ---- ground --------------------------------------------------------------

  void _shadow() {
    final lift = (-p[P.rootY]).clamp(0.0, 30.0);
    final sitting = p[P.office] > 0.5;
    final w = (sitting ? 22.0 : 26.0) * p[P.shadow] * (1 - lift / 50);
    if (w <= 0.5) return;
    final cx = (p[P.rootX] + p[P.bodyX] * 0.4) * facing;
    c.drawOval(
        Rect.fromCenter(center: Offset(cx, 0.5), width: w * 2, height: w * 0.38),
        _fill(const Color(0xFF2B1D14), 0.22 * (1 - lift / 40)));
  }

  void _pin(double alpha) {
    if (alpha <= 0.01) return;
    c.save();
    c.rotate(p[P.pinWobble] * 0.55);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-5.5, -8, -5.5, -11.5)
      ..arcToPoint(const Offset(5.5, -11.5), radius: const Radius.circular(5.5))
      ..quadraticBezierTo(5.5, -8, 0, 0)
      ..close();
    c.drawPath(path, _fill(k.scarf, alpha));
    c.drawPath(path, _ink..color = k.ink.withValues(alpha: alpha)..strokeWidth = 1.3);
    c.drawCircle(const Offset(0, -11.5), 2.1, _fill(const Color(0xFFFFFFFF), alpha));
    c.restore();
  }

  void _speedLines() {
    final a = p[P.speedLines].clamp(0.0, 1.0);
    final t = p[P.scarfPhase];
    final paint = Paint()
      ..color = k.ink.withValues(alpha: 0.45 * a)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = -42.0 + i * 9 + (i.isEven ? 2 : 0);
      final off = ((t * 3 + i * 7) % 14);
      final x0 = (-40.0 - off) * facing, x1 = (-28.0 - off + i * 2) * facing;
      c.drawLine(Offset(x0, y), Offset(x1, y), paint);
    }
  }

  void _dust() {
    final a = p[P.dust].clamp(0.0, 1.0);
    for (var i = 0; i < 4; i++) {
      final r = 3.0 + i * 1.3 + (1 - a) * 4;
      final x = (-14.0 + i * 9 - (1 - a) * 6) * facing;
      c.drawCircle(Offset(x, -r * 0.6), r, _fill(const Color(0xFFD9C7A8), 0.75 * a));
    }
  }

  // ---- body parts ------------------------------------------------------------

  void _leg(P xK, P yK, P a1K, P a2K, double lenScale, {bool far = false}) {
    if (lenScale < 0.05) return;
    final root = Offset(p[xK], p[yK]);
    final l = 12.0 * lenScale;
    final a1 = p[a1K], a2 = a1 + p[a2K];
    final knee = root + Offset(math.sin(a1), math.cos(a1)) * l;
    final paw = knee + Offset(math.sin(a2), math.cos(a2)) * l;
    _limb([root, knee, paw], 5.6, far ? k.bodyFar : k.body);
    final pawPath = _ellipse(paw + Offset(math.sin(a2) * 0.6 + 0.8, 0.2), 3.4, 2.3, 0, n: 8, jitter: 0.15);
    _shape(pawPath, far ? k.bodyFar : k.paw);
  }

  Offset _pawOf(P xK, P yK, P a1K, P a2K, double lenScale) {
    final root = Offset(p[xK], p[yK]);
    final l = 12.0 * lenScale;
    final a1 = p[a1K], a2 = a1 + p[a2K];
    return root + Offset(math.sin(a1), math.cos(a1)) * l + Offset(math.sin(a2), math.cos(a2)) * l;
  }

  Offset get _nearPaw => _pawOf(P.fnX, P.fnY, P.fnA1, P.fnA2, p[P.legLen]);
  Offset get _farPaw => _pawOf(P.ffX, P.ffY, P.ffA1, P.ffA2, p[P.legLen]);

  void _body() {
    final center = Offset(p[P.bodyX], p[P.bodyY]);
    final rot = p[P.bodyRot];
    final len = p[P.bodyLen], h = p[P.bodyH];
    // Slightly pear-shaped: chest rounder than the rump.
    final pts = <Offset>[];
    for (var i = 0; i < 14; i++) {
      final ang = 2 * math.pi * i / 14;
      final x = math.cos(ang), y = math.sin(ang);
      final chest = x > 0 ? 1.08 : 1.0;
      pts.add(center + _rot(Offset(len * x, h * y * chest), rot));
    }
    final body = _blob(pts);
    c.drawPath(body, _fill(k.body));
    c.save();
    c.clipPath(body);
    // Cream belly.
    c.drawOval(
        Rect.fromCenter(center: center + _rot(Offset(len * 0.15, h * 0.85), rot), width: len * 1.5, height: h * 1.1),
        _fill(k.belly));
    // Orange patch over the back and rump.
    final pc = center + _rot(Offset(-len * 0.3, -h * 0.62), rot);
    c.drawPath(_ellipse(pc, len * 0.62, h * 0.72, rot - 0.25, n: 10, jitter: 0.12), _fill(k.bodyPatch));
    c.drawOval(Rect.fromCenter(center: pc + _rot(Offset(len * 0.12, -h * 0.3), rot), width: len * 0.3, height: h * 0.16),
        _fill(const Color(0xFFFFFFFF), 0.75));
    c.restore();
    c.drawPath(body, _ink);

    // Haunch (thigh) for sitting/lying poses.
    final hn = p[P.haunch];
    if (hn > 0.05) {
      final hc = center + _rot(Offset(-len * 0.42, h * 0.38), rot);
      final hp = _ellipse(hc, 9.5 * hn, 10.5 * hn, rot * 0.3, n: 10);
      _shape(hp, k.body);
      c.save();
      c.clipPath(hp);
      c.drawOval(Rect.fromCenter(center: hc + Offset(-2.5 * hn, -3 * hn), width: 9 * hn, height: 7 * hn),
          _fill(k.bodyPatch));
      c.restore();
    }
  }

  void _tail() {
    final base = Offset(p[P.tailX], p[P.tailY]);
    final end = base + Offset(p[P.tailEndX], p[P.tailEndY]);
    final dir = end - base;
    final len = dir.distance.clamp(1.0, 200.0);
    final perp = Offset(-dir.dy, dir.dx) / len;
    final bend = p[P.tailBend];
    final c1 = base + dir * 0.3 + perp * bend;
    final c2 = base + dir * 0.75 + perp * bend * 1.1;
    final pts = <Offset>[];
    const n = 16;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final mt = 1 - t;
      pts.add(base * (mt * mt * mt) + c1 * (3 * mt * mt * t) + c2 * (3 * mt * t * t) + end * (t * t * t));
    }
    // Curl the tip.
    final curl = p[P.tailCurl];
    if (curl.abs() > 0.02) {
      final last = pts.last, prev = pts[pts.length - 2];
      var d = last - prev;
      for (var i = 0; i < 4; i++) {
        d = _rot(d, -0.55 * curl);
        pts.add(pts.last + d * 0.9);
      }
    }
    // Outline, then alternating bands for the stripes.
    final outline = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      outline.lineTo(q.dx, q.dy);
    }
    c.drawPath(
        outline,
        Paint()
          ..color = k.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.4 + inkW * 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < pts.length - 1; i++) {
      final band = i >= 9 && (i ~/ 3).isOdd;
      final w = 5.4 - i * 0.12;
      c.drawLine(
          pts[i],
          pts[i + 1],
          Paint()
            ..color = band ? k.bodyPatch : k.body
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round);
    }
  }

  void _drawHead() {
    final rot = p[P.headRot];
    // Ears first (behind the head outline).
    _ear(const Offset(-5, -8.5), const Offset(-8, -21), p[P.earBack], far: true);
    final head = _blob([
      for (var i = 0; i < 12; i++)
        _hp(14.2 * math.cos(2 * math.pi * i / 12) * (i > 2 && i < 10 ? 0.96 : 1.04),
            12.6 * math.sin(2 * math.pi * i / 12) * (i > 0 && i < 6 ? 1.02 : 0.98)),
    ]);
    c.drawPath(head, _fill(k.fur));
    c.save();
    c.clipPath(head);
    // Muzzle + cheek.
    c.drawOval(Rect.fromCenter(center: _hp(8.5, 5.5), width: 14, height: 9.5), _fill(k.muzzle));
    // Orange patch over the top of the head, with a little shine.
    final patch = _blob([
      for (var i = 0; i < 10; i++)
        _hp(-2.5 + 11.5 * math.cos(2 * math.pi * i / 10), -9.5 + 7.5 * math.sin(2 * math.pi * i / 10)),
    ]);
    c.drawPath(patch, _fill(k.patch));
    c.drawOval(Rect.fromCenter(center: _hp(1.5, -12.2), width: 4.2, height: 1.6), _fill(const Color(0xFFFFFFFF), 0.8));
    _heroInsideHead();
    c.restore();
    c.drawPath(head, _ink);
    _ear(const Offset(5, -9.5), const Offset(6, -23), p[P.earFront]);
    _heroOnHead();

    // Eyes.
    final open = p[P.eyeOpen].clamp(0.0, 1.0);
    final wide = p[P.eyeWide].clamp(0.0, 1.0);
    final look = p[P.eyeLook].clamp(-1.0, 1.0);
    for (final e in [(x: 3.0, s: 0.85), (x: 10.0, s: 1.0)]) {
      final center = _hp(e.x + look * 0.9, -1.2);
      if (open < 0.22) {
        // Closed: happy upward arc (the logo's smile-eyes).
        c.drawArc(Rect.fromCenter(center: center + const Offset(0, 1.2), width: 5 * e.s, height: 3.8 * e.s),
            math.pi + 0.25, math.pi - 0.5, false, _ink..color = k.eye..strokeWidth = 1.6);
        continue;
      }
      final rx = (2.3 + 0.8 * wide) * e.s, ry = (2.9 + 0.9 * wide) * e.s * open;
      if (wide > 0.05) {
        c.drawOval(Rect.fromCenter(center: center, width: rx * 2 + 2.2, height: ry * 2 + 2.2),
            _fill(const Color(0xFFFFFFFF), wide));
      }
      final eye = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
      c.drawOval(eye, _fill(k.eye));
      if (k.eyeOutline) c.drawOval(eye, _ink..strokeWidth = 1.1);
      if (k.eye == k.ink) {
        c.drawCircle(center + Offset(-rx * 0.3, -ry * 0.35), 0.8 * e.s, _fill(const Color(0xFFFFFFFF)));
      }
      // Heavy lid for serious / sleepy looks.
      if (open < 0.85) {
        c.drawLine(center + Offset(-rx - 0.6, -ry + 0.2), center + Offset(rx + 0.6, -ry + 0.2), _ink..strokeWidth = 1.4);
      }
    }
    // Brows: negative = flat & serious, positive = worried.
    final brow = p[P.brow];
    if (brow.abs() > 0.1) {
      final bp = _ink..color = k.eye..strokeWidth = 1.3;
      for (final e in [(x: 3.0, dir: -1.0), (x: 10.0, dir: 1.0)]) {
        final mid = _hp(e.x + look * 0.6, -6.3);
        final tilt = brow * 1.3 * e.dir;
        c.drawLine(mid + Offset(-2.2, -tilt), mid + Offset(2.2, tilt), bp);
      }
    }
    // Nose, mouth, whiskers.
    final nose = _hp(13.2, 2.4);
    c.drawPath(
        Path()
          ..moveTo(nose.dx - 1.8, nose.dy - 1.0)
          ..lineTo(nose.dx + 1.6, nose.dy - 1.2)
          ..lineTo(nose.dx, nose.dy + 1.3)
          ..close(),
        _fill(k.nose));
    final mouth = p[P.mouth].clamp(0.0, 1.0);
    if (mouth > 0.15) {
      c.drawOval(Rect.fromCenter(center: _hp(11.5, 6.6 + mouth), width: 3 + 2 * mouth, height: 2 + 4.5 * mouth),
          _fill(const Color(0xFF7A2E2E)));
    } else {
      final m = _hp(12.6, 4.8);
      c.drawPath(
          Path()
            ..moveTo(m.dx - 2.6, m.dy + 0.5)
            ..quadraticBezierTo(m.dx - 1.3, m.dy + 1.9, m.dx, m.dy)
            ..quadraticBezierTo(m.dx + 1.2, m.dy + 1.9, m.dx + 2.3, m.dy + 0.4),
          _ink..strokeWidth = 1.1);
    }
    final wp = Paint()
      ..color = k.ink.withValues(alpha: 0.45)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final w0 = _hp(14.5, 4.0);
    for (final a in [-0.25, 0.0, 0.25]) {
      c.drawLine(w0, w0 + _rot(Offset(9, a * 9), rot), wp);
    }
    // Blush.
    c.drawOval(Rect.fromCenter(center: _hp(6.2, 3.6), width: 5.2, height: 3.0), _fill(k.blush, 0.8));
    if (p[P.headphones] > 0.01) _headphones(p[P.headphones]);
  }

  /// Big round headphones: a band over the top, a cup on each side.
  void _headphones(double a) {
    const shell = Color(0xFF2B2B33), cushion = Color(0xFF6C63FF), rim = Color(0xFF8A84FF);
    final band = Path()
      ..moveTo(_hp(-11.5, -4).dx, _hp(-11.5, -4).dy)
      ..quadraticBezierTo(_hp(-8, -17).dx, _hp(-8, -17).dy, _hp(0, -17.5).dx, _hp(0, -17.5).dy)
      ..quadraticBezierTo(_hp(8, -17).dx, _hp(8, -17).dy, _hp(12, -4).dx, _hp(12, -4).dy);
    c.drawPath(
        band,
        Paint()
          ..color = k.ink.withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round);
    c.drawPath(
        band,
        Paint()
          ..color = shell.withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round);
    for (final (x, y, r) in [(-12.0, -1.5, 3.9), (12.5, -2.5, 4.2)]) {
      final at = _hp(x, y);
      c.drawCircle(at, r, _fill(shell, a));
      c.drawCircle(at, r, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.3);
      c.drawCircle(at, r * 0.62, _fill(cushion, a));
      c.drawCircle(at + Offset(-r * 0.25, -r * 0.3), r * 0.18, _fill(rim, a));
    }
  }

  // ---- study desk (education) --------------------------------------------------

  void _deskBack(double a) {
    // A little desk lamp on the far end of the table.
    final lamp = p[P.lamp].clamp(0.0, 1.0) * a;
    if (lamp > 0.02) {
      final glow = Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.35 * lamp);
      c.drawOval(Rect.fromCenter(center: const Offset(30, -24), width: 30, height: 16), glow);
    }
    final arm = Paint()
      ..color = const Color(0xFF3F4A55).withValues(alpha: a)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(44, -17), const Offset(44, -31), arm);
    c.drawLine(const Offset(44, -31), const Offset(36, -34), arm);
    final shade = Path()
      ..moveTo(33, -36)
      ..lineTo(40, -36)
      ..lineTo(43, -29)
      ..lineTo(30, -29)
      ..close();
    c.drawPath(shade, _fill(const Color(0xFF2F8F6B), a));
    c.drawPath(shade, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.1);
    if (lamp > 0.02) c.drawCircle(const Offset(36.5, -29), 1.6, _fill(const Color(0xFFFFF1B8), lamp));
  }

  void _deskFront(double a) {
    final ink = _ink..color = k.ink.withValues(alpha: a);
    // Low table.
    final leg = Paint()
      ..color = const Color(0xFF7A5536).withValues(alpha: a)
      ..strokeWidth = 2.4;
    c.drawLine(const Offset(16, -14), const Offset(16, 0), leg);
    c.drawLine(const Offset(42, -14), const Offset(42, 0), leg);
    final top = RRect.fromRectAndRadius(const Rect.fromLTWH(11, -18, 36, 4.2), const Radius.circular(1.2));
    c.drawRRect(top, _fill(CatInk.wood, a));
    c.drawRRect(top, ink);
    // Open notebook seen a little from above, pages fanning.
    final book = Path()
      ..moveTo(17, -18)
      ..lineTo(39, -18)
      ..lineTo(41, -23)
      ..lineTo(19, -23)
      ..close();
    c.drawPath(book, _fill(const Color(0xFFFFFDF5), a));
    c.drawPath(book, ink..strokeWidth = 1.1);
    c.drawLine(const Offset(29, -18), const Offset(30, -23), Paint()
      ..color = k.ink.withValues(alpha: 0.5 * a)
      ..strokeWidth = 0.8);
    // Lines of homework that fill in as the cat writes.
    final progress = p[P.write].clamp(0.0, 1.0);
    final pen = Paint()
      ..color = const Color(0xFF2F5D8A).withValues(alpha: a)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    const rows = 3;
    for (var i = 0; i < rows; i++) {
      final rowP = ((progress * rows) - i).clamp(0.0, 1.0);
      if (rowP <= 0) break;
      final y = -22.2 + i * 1.3;
      final x0 = 31.0 + i * 0.3, w = 8.0 * rowP;
      c.drawLine(Offset(x0, y), Offset(x0 + w, y), pen);
      if (i == 0) c.drawLine(Offset(20, y), Offset(27.5, y), pen); // the sum on the left page
    }
  }

  /// Pencil held in the near front paw.
  void _pencil(double a) {
    final paw = _nearPaw;
    c.save();
    c.translate(paw.dx, paw.dy);
    c.rotate(-0.95);
    final body = const Rect.fromLTWH(-1.1, -8.5, 2.2, 9);
    c.drawRect(body, _fill(const Color(0xFFF7C331), a));
    c.drawRect(body, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 0.8);
    c.drawPath(
        Path()
          ..moveTo(-1.1, 0.5)
          ..lineTo(1.1, 0.5)
          ..lineTo(0, 3)
          ..close(),
        _fill(const Color(0xFFE8C9A0), a));
    c.drawCircle(const Offset(0, 2.6), 0.5, _fill(k.ink, a));
    c.drawRect(const Rect.fromLTWH(-1.1, -8.5, 2.2, 1.6), _fill(const Color(0xFFF28A9A), a));
    c.restore();
    // Paw wraps the pencil.
    c.drawOval(Rect.fromCenter(center: paw, width: 5.8, height: 4.0), _fill(k.paw, a));
    c.drawOval(Rect.fromCenter(center: paw, width: 5.8, height: 4.0), _ink..color = k.ink.withValues(alpha: a));
  }

  // ---- hangout bench --------------------------------------------------------------

  void _benchBack(double a) {
    final ink = _ink..color = k.ink.withValues(alpha: a);
    final leg = Paint()
      ..color = const Color(0xFF4B5763).withValues(alpha: a)
      ..strokeWidth = 2.6;
    c.drawLine(const Offset(-26, -9), const Offset(-28, 0), leg);
    c.drawLine(const Offset(26, -9), const Offset(28, 0), leg);
    final seat = RRect.fromRectAndRadius(const Rect.fromLTWH(-34, -12.5, 68, 3.8), const Radius.circular(1.4));
    c.drawRRect(seat, _fill(const Color(0xFFB07A4A), a));
    c.drawRRect(seat, ink);
    final slat = RRect.fromRectAndRadius(const Rect.fromLTWH(-34, -8.2, 68, 2.2), const Radius.circular(1));
    c.drawRRect(slat, _fill(const Color(0xFF9A6A43), a));
    c.drawRRect(slat, ink..strokeWidth = 1.0);
    // A little speaker on the bench, pulsing with the beat.
    final beat = p[P.beat].clamp(0.0, 1.0);
    final box = RRect.fromRectAndRadius(const Rect.fromLTWH(-33, -22.5, 9, 10), const Radius.circular(1.6));
    c.drawRRect(box, _fill(const Color(0xFF2B2B33), a));
    c.drawRRect(box, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.2);
    c.drawCircle(const Offset(-28.5, -18.5), 2.6 + 0.4 * beat, _fill(const Color(0xFF6C63FF), a));
    c.drawCircle(const Offset(-28.5, -18.5), 1.0, _fill(const Color(0xFF15151A), a));
    if (p[P.notes] > 0.02) {
      final ring = Paint()
        ..color = const Color(0xFF6C63FF).withValues(alpha: 0.5 * beat * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      c.drawCircle(const Offset(-28.5, -18.5), 4.5 + 2.5 * (1 - beat), ring);
    }
  }

  /// Costume details that sit inside the head outline (clipped to it).
  void _heroInsideHead() {
    switch (k.look) {
      case HeroLook.spider:
        final web = Paint()
          ..color = const Color(0xFF8E1424)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round;
        final hub = _hp(7, 1);
        for (var i = 0; i < 10; i++) {
          final a = 2 * math.pi * i / 10 + p[P.headRot];
          c.drawLine(hub, hub + Offset(math.cos(a), math.sin(a)) * 32, web);
        }
        for (final r in [6.0, 11.0, 16.5, 23.0]) {
          c.drawCircle(hub, r, web);
        }
      case HeroLook.iron:
        // Gold faceplate.
        final plate = _blob([
          for (var i = 0; i < 10; i++)
            _hp(7.5 + 9.2 * math.cos(2 * math.pi * i / 10), 1.6 + 9.6 * math.sin(2 * math.pi * i / 10)),
        ], jitter: 0.15);
        c.drawPath(plate, _fill(k.muzzle));
        c.drawPath(plate, _ink..strokeWidth = 1.0);
      case HeroLook.superman:
        // The little curl of hair on the forehead.
        c.drawArc(Rect.fromCircle(center: _hp(7.2, -4.6), radius: 1.7), 0.4, math.pi * 1.5, false,
            _ink..color = k.patch..strokeWidth = 1.5);
      case HeroLook.wonder:
        // Gold tiara with a red star.
        final t = [
          _hp(-15, -8.2), _hp(15, -8.8), _hp(15, -5.8), _hp(8.6, -5.5),
          _hp(6.6, -3.4), _hp(4.6, -5.4), _hp(-15, -5.0),
        ];
        final tiara = Path()..moveTo(t[0].dx, t[0].dy);
        for (final q in t.skip(1)) {
          tiara.lineTo(q.dx, q.dy);
        }
        tiara.close();
        c.drawPath(tiara, _fill(const Color(0xFFF2B632)));
        c.drawPath(tiara, _ink..strokeWidth = 1.0);
        final sc = _hp(6.6, -6.2);
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + math.pi * i / 5 + p[P.headRot];
          final q = sc + Offset(math.cos(a), math.sin(a)) * (i.isEven ? 1.9 : 0.85);
          if (i == 0) {
            star.moveTo(q.dx, q.dy);
          } else {
            star.lineTo(q.dx, q.dy);
          }
        }
        star.close();
        c.drawPath(star, _fill(const Color(0xFFD7263D)));
      default:
        break;
    }
  }

  /// Costume details drawn over the finished head.
  void _heroOnHead() {
    if (k.look != HeroLook.catwoman) return;
    // Goggles pushed up on the forehead.
    final l = _hp(2.6, -8.6), r = _hp(9.4, -9.0);
    c.drawLine(_hp(-9, -8.4), _hp(13.5, -8.2), _ink..strokeWidth = 1.6);
    for (final (at, rad) in [(l, 2.6), (r, 3.0)]) {
      c.drawCircle(at, rad, _fill(const Color(0xFFF7A63A)));
      c.drawCircle(at, rad, _ink..strokeWidth = 1.1);
      c.drawCircle(at + Offset(-rad * 0.35, -rad * 0.35), 0.7, _fill(const Color(0xFFFFFFFF), 0.8));
    }
  }

  void _ear(Offset base, Offset tip, double back, {bool far = false}) {
    final ang = -back * 1.0;
    final b = base;
    // Wind presses the ears flatter (shorter), as well as back.
    final t = b + _rot(tip - b, ang) * (1 - 0.3 * p[P.earFlat].clamp(0.0, 1.0));
    final w = 5.4;
    final dir = (t - b);
    final perp = Offset(-dir.dy, dir.dx) / dir.distance;
    final l = b - perp * w, r = b + perp * w;
    final pts = [_hp(l.dx, l.dy), _hp(t.dx, t.dy), _hp(r.dx, r.dy)];
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..quadraticBezierTo(
          (pts[0].dx + pts[1].dx) / 2 - perp.dx, (pts[0].dy + pts[1].dy) / 2 - perp.dy, pts[1].dx, pts[1].dy);
    if (far) {
      // Street-cat ear notch near the tip.
      final n1 = Offset.lerp(pts[1], pts[2], 0.18)!;
      final n2 = Offset.lerp(pts[1], pts[2], 0.34)!;
      final nm = Offset.lerp(n1, n2, 0.5)! + (Offset.lerp(pts[0], pts[2], 0.5)! - n1) * 0.18;
      path
        ..lineTo(n1.dx, n1.dy)
        ..lineTo(nm.dx, nm.dy)
        ..lineTo(n2.dx, n2.dy);
    }
    path
      ..quadraticBezierTo(
          (pts[1].dx + pts[2].dx) / 2 + perp.dx, (pts[1].dy + pts[2].dy) / 2 + perp.dy, pts[2].dx, pts[2].dy)
      ..close();
    c.drawPath(path, _fill(far ? k.patch : k.fur));
    c.drawPath(path, _ink);
    // Inner ear.
    final inner = Path()
      ..moveTo(Offset.lerp(pts[0], pts[2], 0.3)!.dx, Offset.lerp(pts[0], pts[2], 0.3)!.dy)
      ..lineTo(Offset.lerp(pts[1], Offset.lerp(pts[0], pts[2], 0.5)!, 0.3)!.dx,
          Offset.lerp(pts[1], Offset.lerp(pts[0], pts[2], 0.5)!, 0.3)!.dy)
      ..lineTo(Offset.lerp(pts[0], pts[2], 0.72)!.dx, Offset.lerp(pts[0], pts[2], 0.72)!.dy)
      ..close();
    c.drawPath(inner, _fill(k.earPink, far ? 0.6 : 1));
  }

  // ---- scarf -------------------------------------------------------------------

  Offset get _neck => _head + _rot(const Offset(-3.5, 13.2), p[P.headRot] * 0.5);

  void _scarfOnNeck() {
    final a = p[P.scarfNeck].clamp(0.0, 1.0);
    if (a < 0.02) return;
    final neck = _neck;
    final flow = p[P.scarfFlow].clamp(0.0, 1.0);
    final ph = p[P.scarfPhase];
    // Trailing ends: hanging down → streaming straight back.
    final ends = a * (1 - p[P.blanket].clamp(0.0, 1.0));
    for (var n = 0; n < (ends > 0.02 ? 2 : 0); n++) {
      final pts = <Offset>[];
      // Angle of the ribbon: pi/2 hangs down, pi streams straight back.
      final baseAng = (math.pi / 2 + 0.3) * (1 - flow) + (math.pi * 0.97) * flow - n * 0.2;
      final length = 10.0 + 10 * flow - n * 2.5;
      pts.add(neck + const Offset(-3, 2.5));
      for (var i = 1; i <= 6; i++) {
        final wave = math.sin(ph + i * 0.9 + n) * (0.12 + 0.3 * flow) * i / 6;
        pts.add(pts.last + _dirFromAngle(baseAng + wave) * (length / 6));
      }
      _limb(pts, 4.2 - n * 0.6, n == 0 ? k.scarf : k.scarfDark, alpha: ends);
      // Fringe at the end.
      final end = pts.last;
      final fp = Paint()
        ..color = k.scarfDark.withValues(alpha: a)
        ..strokeWidth = 0.9;
      for (var i = -1; i <= 1; i++) {
        c.drawLine(end, end + _dirFromAngle(baseAng + i * 0.25) * 2.6, fp);
      }
    }
  }

  void _scarfBand() {
    final a = p[P.scarfNeck].clamp(0.0, 1.0);
    if (a < 0.02) return;
    final neck = _neck;
    // The band around the neck.
    final band = _ellipse(neck, 8.6, 3.9, -0.35 + p[P.headRot] * 0.5 + p[P.bodyRot] * 0.4, n: 10, jitter: 0.2);
    _shape(band, k.scarf, a);
    c.drawLine(neck + const Offset(-5, 0.8), neck + const Offset(5, -1.6),
        Paint()
          ..color = k.scarfDark.withValues(alpha: a)
          ..strokeWidth = 1.1);
    // Knot.
    _shape(_ellipse(neck + const Offset(-4.5, 2.2), 2.6, 2.2, 0, n: 8, jitter: 0.15), k.scarfDark, a);
  }

  /// "Down" = pi/2, "back" (towards -x) = pi.
  Offset _dirFromAngle(double ang) => Offset(math.cos(ang), math.sin(ang));

  void _scarfOverFace(double a) {
    final h = _head;
    final drape = Path()
      ..moveTo(h.dx - 12, h.dy - 6)
      ..quadraticBezierTo(h.dx + 2, h.dy - 17, h.dx + 16, h.dy - 5)
      ..quadraticBezierTo(h.dx + 19, h.dy + 4, h.dx + 14, h.dy + 9 + 3 * a)
      ..lineTo(h.dx + 8, h.dy + 7)
      ..quadraticBezierTo(h.dx + 2, h.dy + 3, h.dx - 4, h.dy + 6)
      ..close();
    c.save();
    c.translate(0, -8 * (1 - a));
    _shape(drape, k.scarf, a);
    c.drawLine(Offset(h.dx - 6, h.dy - 7), Offset(h.dx + 14, h.dy - 3),
        Paint()
          ..color = k.scarfDark.withValues(alpha: a)
          ..strokeWidth = 1.2);
    c.restore();
  }

  // ---- props --------------------------------------------------------------------

  void _chaGlass() {
    final a = p[P.cha].clamp(0.0, 1.0);
    final paw = _nearPaw + Offset(p[P.chaX] + 1.5, p[P.chaY] - 4.5);
    c.save();
    c.translate(paw.dx, paw.dy);
    c.rotate(-p[P.chaTilt]);
    final glass = Path()
      ..moveTo(-3.4, -4.6)
      ..lineTo(3.4, -4.6)
      ..lineTo(2.5, 4.2)
      ..lineTo(-2.5, 4.2)
      ..close();
    c.drawPath(glass, _fill(CatInk.glass, a));
    final teaLevel = Path()
      ..moveTo(-3.0, -1.6)
      ..lineTo(3.0, -1.6)
      ..lineTo(2.5, 4.2)
      ..lineTo(-2.5, 4.2)
      ..close();
    c.drawPath(teaLevel, _fill(CatInk.tea, a));
    c.drawPath(glass, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.1);
    c.restore();
    // Paw wraps the glass.
    c.drawOval(Rect.fromCenter(center: _nearPaw, width: 6.4, height: 4.4), _fill(k.paw, a));
    c.drawOval(Rect.fromCenter(center: _nearPaw, width: 6.4, height: 4.4), _ink..color = k.ink.withValues(alpha: a));
    // Steam.
    final st = p[P.steam].clamp(0.0, 1.0) * a;
    if (st > 0.02) {
      final t = p[P.scarfPhase] + p[P.time] * 2;
      final sp = Paint()
        ..color = const Color(0xFF8C8C8C).withValues(alpha: 0.55 * st)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 2; i++) {
        final x = paw.dx - 1 + i * 2.4;
        final y0 = paw.dy - 6;
        final path = Path()..moveTo(x, y0);
        final blow = p[P.blow].clamp(0.0, 1.0);
        for (var k = 1; k <= 4; k++) {
          // Blowing bends the steam away from the face.
          path.lineTo(x + math.sin(t * 1.3 + k + i) * 1.3 * (1 - 0.6 * blow) + blow * k * k * 0.9,
              y0 - k * 2.4 * (1 - 0.35 * blow));
        }
        c.drawPath(path, sp);
      }
    }
  }

  void _paperMap() {
    final vis = p[P.mapVis].clamp(0.0, 1.0);
    final open = p[P.mapOpen].clamp(0.0, 1.2);
    final center = Offset.lerp(_nearPaw, _farPaw, 0.5)! + const Offset(1, -6);
    final w = 7 + 21 * open, h = 15.0;
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(p[P.mapRot] + 0.08);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    c.drawRect(rect, _fill(CatInk.paper, vis));
    // Fold panels.
    const panels = 4;
    for (var i = 0; i < panels; i++) {
      final x0 = rect.left + w * i / panels;
      if (i.isOdd) {
        c.drawRect(Rect.fromLTWH(x0, rect.top, w / panels, h), _fill(const Color(0xFFDCCDA6), vis));
      }
    }
    // Roads & a route.
    c.drawLine(Offset(rect.left + 2, 2), Offset(rect.right - 2, -1.5),
        Paint()
          ..color = const Color(0xFFB9A57E).withValues(alpha: vis)
          ..strokeWidth = 1.6);
    c.drawLine(Offset(-w * 0.15, rect.top + 1.5), Offset(w * 0.1, rect.bottom - 1.5),
        Paint()
          ..color = const Color(0xFFB9A57E).withValues(alpha: vis)
          ..strokeWidth = 1.3);
    if (open > 0.5) {
      final route = Path()
        ..moveTo(rect.left + 3, rect.bottom - 3)
        ..quadraticBezierTo(0, -h * 0.4, rect.right - 4, rect.top + 4);
      c.drawPath(
          route,
          Paint()
            ..color = k.scarf.withValues(alpha: vis * 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1);
      c.drawCircle(Offset(rect.right - 4, rect.top + 4), 1.6, _fill(k.scarf, vis));
    }
    c.drawRect(rect, _ink..color = k.ink.withValues(alpha: vis)..strokeWidth = 1.2);
    c.restore();
    // Paws holding the edges.
    for (final paw in [_nearPaw, _farPaw]) {
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _fill(k.paw, vis));
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _ink..color = k.ink.withValues(alpha: vis));
    }
  }

  void _glassesOnFace(double a) {
    final l = _hp(3.0, -1.2), r = _hp(10.4, -1.4);
    _glasses(l, r, a, 4.3);
  }

  void _glasses(Offset l, Offset r, double a, double rad) {
    final gp = Paint()
      ..color = k.ink.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    c.drawCircle(l, rad * 0.85, _fill(const Color(0x66D7EEF7), a));
    c.drawCircle(r, rad, _fill(const Color(0x66D7EEF7), a));
    c.drawCircle(l, rad * 0.85, gp);
    c.drawCircle(r, rad, gp);
    c.drawLine(l + Offset(rad * 0.85, 0), r - Offset(rad, 0), gp);
    c.drawLine(l - Offset(rad * 0.85, 0), l - Offset(rad * 0.85 + 4, -1.5), gp);
    c.drawCircle(r + Offset(-rad * 0.4, -rad * 0.4), 0.9, _fill(const Color(0xFFFFFFFF), a * 0.9));
  }

  void _snotBubble() {
    final b = p[P.bubble].clamp(0.0, 1.0);
    final nose = _hp(14.5, 3.0);
    final r = 1.0 + 4.8 * b;
    final center = nose + Offset(r * 0.8, -r * 0.3);
    c.drawCircle(center, r, _fill(const Color(0x99BFE4F5)));
    c.drawCircle(center, r, Paint()
      ..color = const Color(0xFF6FA5C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9);
    c.drawCircle(center + Offset(-r * 0.35, -r * 0.4), r * 0.22, _fill(const Color(0xFFFFFFFF), 0.9));
  }

  // ---- office -------------------------------------------------------------------

  void _officeBack(double a) {
    final cx = p[P.chairX];
    c.save();
    c.translate(cx, 0);
    final metal = Paint()
      ..color = CatInk.metal.withValues(alpha: a)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    // Base + wheels.
    c.drawLine(const Offset(-19, -4), const Offset(5, -4), metal);
    c.drawLine(const Offset(-7, -4), const Offset(-7, -17), metal..strokeWidth = 3);
    final roll = -cx * 0.6;
    for (final x in [-18.0, -7.0, 4.0]) {
      c.drawCircle(Offset(x, -1.8), 2.1, _fill(const Color(0xFF2E2E2E), a));
      c.drawLine(Offset(x, -1.8), Offset(x, -1.8) + Offset(math.cos(roll), math.sin(roll)) * 1.8,
          Paint()
            ..color = const Color(0xFFBBBBBB).withValues(alpha: a)
            ..strokeWidth = 0.7);
    }
    // Backrest with the scarf draped over it.
    final back = RRect.fromRectAndRadius(const Rect.fromLTWH(-24, -47, 7, 29), const Radius.circular(3));
    c.drawRRect(back, _fill(const Color(0xFF3F4A55), a));
    c.drawRRect(back, _ink..color = k.ink.withValues(alpha: a));
    final drape = (1 - p[P.scarfNeck]).clamp(0.0, 1.0) * a;
    if (drape > 0.02) {
      final sc = Path()
        ..moveTo(-26, -45)
        ..quadraticBezierTo(-20, -50, -15, -45)
        ..lineTo(-14, -30)
        ..quadraticBezierTo(-15.5, -27, -17, -30)
        ..lineTo(-18, -41)
        ..lineTo(-24, -41)
        ..lineTo(-26, -24)
        ..quadraticBezierTo(-27.5, -21, -29, -25)
        ..close();
      _shape(sc, k.scarf, drape);
    }
    // Seat.
    final seat = RRect.fromRectAndRadius(const Rect.fromLTWH(-21, -21.5, 28, 5.5), const Radius.circular(2.5));
    c.drawRRect(seat, _fill(const Color(0xFF4B5763), a));
    c.drawRRect(seat, _ink..color = k.ink.withValues(alpha: a));
    c.restore();
  }

  void _officeFront(double a) {
    final ink = _ink..color = k.ink.withValues(alpha: a);
    // Desk.
    final top = Rect.fromLTWH(17, -37, 52, 4.2);
    c.drawRect(top, _fill(CatInk.wood, a));
    c.drawRect(top, ink);
    final leg = Paint()
      ..color = const Color(0xFF6E4A2E).withValues(alpha: a)
      ..strokeWidth = 2.6;
    c.drawLine(const Offset(21, -33), const Offset(21, 0), leg);
    c.drawLine(const Offset(65, -33), const Offset(65, 0), leg);
    // PC tower under the desk.
    final tower = RRect.fromRectAndRadius(const Rect.fromLTWH(46, -27, 12, 26), const Radius.circular(1.5));
    c.drawRRect(tower, _fill(const Color(0xFF39424B), a));
    c.drawRRect(tower, ink);
    c.drawCircle(const Offset(52, -23), 1.0, _fill(const Color(0xFF7CFC9A), a));

    // Monitor (wobbles when bonked).
    c.save();
    c.translate(47, -37);
    c.rotate(p[P.monWobble] * 0.08);
    c.drawRect(const Rect.fromLTWH(-2, -6, 4, 6), _fill(CatInk.metal, a));
    final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -32, 35, 26), const Radius.circular(2.5));
    c.drawRRect(frame, _fill(const Color(0xFF30363C), a));
    c.drawRRect(frame, ink);
    final screen = const Rect.fromLTWH(-15.5, -29.5, 30, 21);
    final flash = p[P.enterFlash].clamp(0.0, 1.0);
    c.drawRect(screen, _fill(Color.lerp(CatInk.screen, const Color(0xFFE8FFF0), flash * 0.8)!, a));
    c.save();
    c.clipRect(screen);
    // Lines of "code" that grow as the cat types.
    final progress = p[P.screenText];
    final tp = Paint()
      ..color = CatInk.screenText.withValues(alpha: a)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final lines = (progress * 7).floor();
    double lastX = screen.left + 3, lastY = screen.top + 3;
    for (var i = 0; i <= lines && i < 7; i++) {
      final full = 6 + (hashNoise(i, 3).abs() * 16);
      final w = i < lines ? full : full * ((progress * 7) % 1);
      final y = screen.top + 3 + i * 2.8;
      final x0 = screen.left + 3 + (i % 3 == 1 ? 3 : 0);
      c.drawLine(Offset(x0, y), Offset(x0 + w, y), tp);
      lastX = x0 + w;
      lastY = y;
    }
    final fish = p[P.fish].clamp(0.0, 1.0);
    if (fish < 0.5) {
      final blinkOn = (p[P.time] * 2).floor().isEven;
      if (blinkOn) c.drawRect(Rect.fromLTWH(lastX + 1, lastY - 1.2, 1.6, 2.6), _fill(CatInk.screenText, a));
    } else {
      final fx = screen.left + screen.width * p[P.fishX];
      final fy = screen.top + screen.height * p[P.fishY];
      _fishCursor(Offset(fx, fy), a * (fish - 0.5) * 2);
    }
    c.restore();
    // Glasses hanging on the monitor corner.
    final gm = p[P.glassesMon].clamp(0.0, 1.0) * a;
    if (gm > 0.02) {
      c.save();
      c.translate(14, -31);
      c.rotate(0.5);
      _glasses(const Offset(-2.4, 4.5), const Offset(4.4, 5.2), gm, 3.3);
      c.restore();
    }
    c.restore();

    // Keyboard with a flashing key and a big Enter key.
    final kb = Path()
      ..moveTo(19, -37)
      ..lineTo(39, -37)
      ..lineTo(41, -39.4)
      ..lineTo(21, -39.4)
      ..close();
    c.drawPath(kb, _fill(const Color(0xFFD6D9DC), a));
    c.drawPath(kb, ink..strokeWidth = 1.1);
    final kf = p[P.keyFlash].clamp(0.0, 1.0);
    if (kf > 0.05) {
      final x = 23 + ((p[P.time] * 13).floor() % 5) * 3.0;
      c.drawRect(Rect.fromLTWH(x, -39, 2.2, 1.6), _fill(const Color(0xFFFFFFFF), kf * a));
    }
    final enter = Rect.fromLTWH(35.5, -39.6, 4.2, 2.2);
    c.drawRect(enter, _fill(Color.lerp(const Color(0xFF9AA3AB), k.scarf, p[P.impact].clamp(0.0, 1.0))!, a));
  }

  void _fishCursor(Offset at, double a) {
    final body = Path()
      ..moveTo(at.dx - 4, at.dy)
      ..quadraticBezierTo(at.dx, at.dy - 3, at.dx + 4, at.dy)
      ..quadraticBezierTo(at.dx, at.dy + 3, at.dx - 4, at.dy)
      ..close();
    c.drawPath(body, _fill(const Color(0xFFFFC94D), a));
    c.drawPath(
        Path()
          ..moveTo(at.dx - 3.6, at.dy)
          ..lineTo(at.dx - 6.4, at.dy - 2.4)
          ..lineTo(at.dx - 6.4, at.dy + 2.4)
          ..close(),
        _fill(const Color(0xFFFFA62B), a));
    c.drawCircle(at + const Offset(2.2, -0.6), 0.6, _fill(k.ink, a));
  }

  // ---- home -----------------------------------------------------------------------

  void _homeBack(double a) {
    // Woven mat (shital pati) and a pillow.
    final mat = RRect.fromRectAndRadius(const Rect.fromLTWH(-40, -3, 78, 4), const Radius.circular(1.5));
    c.drawRRect(mat, _fill(const Color(0xFFD9BE83), a));
    final weave = Paint()
      ..color = const Color(0xFFB18E4E).withValues(alpha: a)
      ..strokeWidth = 0.8;
    for (var x = -38.0; x < 37; x += 4) {
      c.drawLine(Offset(x, -2.6), Offset(x + 2, 0.6), weave);
    }
    // The pillow is for sleeping: it steps aside while the cat does other things.
    final busy = [p[P.bucket], p[P.plate], p[P.tv], p[P.litter], p[P.phone]].reduce(math.max).clamp(0.0, 1.0);
    final pa = a * (1 - busy);
    if (pa > 0.02) {
      final pillow = _ellipse(const Offset(26, -6.5), 11, 5.5, -0.05, n: 10, jitter: 0.2);
      _shape(pillow, CatInk.pillow, pa);
      c.drawLine(const Offset(17, -6), const Offset(35, -7), Paint()
        ..color = const Color(0xFF8FB3D9).withValues(alpha: pa)
        ..strokeWidth = 1);
    }
  }

  void _blanket(double cover, double overHead) {
    final rise = (p[P.bodyH] - 9.5) * 1.2;
    final kick = p[P.kick].clamp(0.0, 1.0);
    final left = -36.0, right = -36 + 52 * cover;
    final path = Path()
      ..moveTo(left, 0)
      ..lineTo(left - 1, -14 - rise * 0.4)
      ..quadraticBezierTo(left + 6, -19 - rise - 4 * kick, -14, -20 - rise - 5 * kick)
      ..quadraticBezierTo(right - 12, -23 - rise, right, -17 - rise * 0.5)
      ..lineTo(right + 2, 0)
      ..close();
    _shape(path, CatInk.kantha);
    // Nakshi-kantha style running stitches and a little flower.
    final stitch = Paint()
      ..color = CatInk.kanthaStitch
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var row = 0; row < 3; row++) {
      final y = -4.0 - row * 5 - rise * (row / 3);
      for (var x = left + 2; x < right - 3; x += 4.2) {
        c.drawLine(Offset(x, y), Offset(x + 2.2, y - 0.3), stitch);
      }
    }
    final fc = Offset((left + right) / 2, -11 - rise * 0.5);
    for (var i = 0; i < 5; i++) {
      final ang = 2 * math.pi * i / 5;
      c.drawCircle(fc + Offset(math.cos(ang), math.sin(ang)) * 2.2, 1.3, _fill(k.scarf));
    }
    c.drawCircle(fc, 1.1, _fill(const Color(0xFFFFD166)));
    // Red border along the top edge.
    c.drawPath(
        Path()
          ..moveTo(left - 1, -14 - rise * 0.4)
          ..quadraticBezierTo(left + 6, -19 - rise - 4 * kick, -14, -20 - rise - 5 * kick)
          ..quadraticBezierTo(right - 12, -23 - rise, right, -17 - rise * 0.5),
        Paint()
          ..color = k.scarf
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
  }

  void _blanketOverHead(double a) {
    final h = _head;
    final path = Path()
      ..moveTo(h.dx - 18, h.dy + 8)
      ..quadraticBezierTo(h.dx - 6, h.dy - 22, h.dx + 14, h.dy - 10)
      ..quadraticBezierTo(h.dx + 20, h.dy + 2, h.dx + 12, h.dy + 10)
      ..close();
    _shape(path, CatInk.kantha, a);
    final stitch = Paint()
      ..color = CatInk.kanthaStitch.withValues(alpha: a)
      ..strokeWidth = 0.9;
    for (var x = h.dx - 10; x < h.dx + 10; x += 4) {
      c.drawLine(Offset(x, h.dy - 4), Offset(x + 2, h.dy - 4.5), stitch);
    }
  }


  // ---- home life ------------------------------------------------------------------

  Paint _inkA(double a, [double w = inkW]) => _ink
    ..color = k.ink.withValues(alpha: a.clamp(0.0, 1.0))
    ..strokeWidth = w;

  /// Blue plastic bucket (balti) behind the cat.
  void _bucket(double a) {
    final body = Path()
      ..moveTo(21, -17)
      ..lineTo(39, -17)
      ..lineTo(37, 0)
      ..lineTo(23, 0)
      ..close();
    c.drawPath(body, _fill(const Color(0xFF2F80C8), a));
    c.drawPath(body, _inkA(a));
    c.drawLine(const Offset(22, -12), const Offset(38, -12), Paint()
      ..color = const Color(0xFF5FA3E0).withValues(alpha: a)
      ..strokeWidth = 1.2);
    c.drawOval(Rect.fromCenter(center: const Offset(30, -17), width: 18, height: 3.6), _fill(const Color(0xFF9FD3F0), a));
    c.drawOval(Rect.fromCenter(center: const Offset(30, -17), width: 18, height: 3.6), _inkA(a, 1.1));
    c.drawPath(
        Path()
          ..moveTo(22, -16)
          ..quadraticBezierTo(30, -29, 38, -16),
        _inkA(a, 1.0)..style = PaintingStyle.stroke);
  }

  /// Plastic mug in the near paw.
  void _mug(double a) {
    final paw = _nearPaw;
    final r = Rect.fromCenter(center: paw + const Offset(1.5, -4.5), width: 6, height: 6.5);
    final mug = RRect.fromRectAndRadius(r, const Radius.circular(1.2));
    c.drawRRect(mug, _fill(const Color(0xFFF2C14E), a));
    c.drawRRect(mug, _inkA(a, 1.1));
    c.drawArc(Rect.fromCenter(center: r.centerRight + const Offset(0.6, 0), width: 4, height: 4.4), -1.4, 2.8, false,
        _inkA(a, 1.1)..style = PaintingStyle.stroke);
    c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _fill(k.paw, a));
    c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _inkA(a));
  }

  /// Water thrown over the head (0..1), then shaken off (1..2).
  void _splash(double s) {
    const water = Color(0xFF7CC4E8);
    void drop(Offset at, double sz, double a) {
      final d = Path()
        ..moveTo(at.dx, at.dy - 2.4 * sz)
        ..quadraticBezierTo(at.dx + 1.8 * sz, at.dy + 0.6 * sz, at.dx, at.dy + 1.2 * sz)
        ..quadraticBezierTo(at.dx - 1.8 * sz, at.dy + 0.6 * sz, at.dx, at.dy - 2.4 * sz)
        ..close();
      c.drawPath(d, _fill(water, a));
      c.drawPath(d, _inkA(a, 0.7));
    }

    final h = _head;
    if (s <= 1) {
      final a = math.sin(math.pi * s);
      for (var i = 0; i < 7; i++) {
        drop(h + Offset(-11 + i * 3.6, -30 + 26 * s + (i.isOdd ? 3 : 0)), 1.0, a);
      }
    } else {
      final u = s - 1;
      for (var i = 0; i < 8; i++) {
        final ang = 2 * math.pi * i / 8 + 0.3;
        drop(h + Offset(math.cos(ang), math.sin(ang)) * (12 + 14 * u), 0.8, 1 - u);
      }
    }
  }

  /// Soap foam on top of the head.
  void _foam(double a) {
    for (final (x, y, r) in [(-7.0, -14.0, 3.4), (-2.0, -17.0, 3.8), (4.0, -16.0, 3.3), (-4.0, -11.0, 2.6), (8.0, -12.5, 2.4)]) {
      final at = _hp(x, y);
      c.drawCircle(at, r * a, _fill(const Color(0xFFFFFFFF), a));
      c.drawCircle(at, r * a, _inkA(a * 0.6, 0.7)..style = PaintingStyle.stroke);
    }
  }

  /// A plate of rice and a fish on the mat; the fish turns into bones as [bite] goes to 1.
  void _plate(double a, double bite) {
    c.save();
    c.translate(-4, 0);
    c.scale(1.25);
    c.drawOval(Rect.fromCenter(center: const Offset(27, -1.6), width: 24, height: 5.2), _fill(const Color(0xFFFFFFFF), a));
    c.drawOval(Rect.fromCenter(center: const Offset(27, -1.6), width: 24, height: 5.2), _inkA(a, 1.1));
    c.drawOval(Rect.fromCenter(center: const Offset(27, -1.9), width: 18, height: 3.2),
        Paint()
          ..color = const Color(0xFF5B8FD0).withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    // Rice.
    final rice = _ellipse(const Offset(22.5, -3.6), 5.2, 2.6, 0, n: 9, jitter: 0.25);
    _shape(rice, const Color(0xFFFFFCF2), a);
    // Fish (eaten from the tail end).
    final fishLen = 10 * (1 - 0.8 * bite);
    final head = const Offset(35, -4.2);
    if (bite < 0.95) {
      final body = Path()
        ..moveTo(head.dx, head.dy)
        ..quadraticBezierTo(head.dx - fishLen * 0.5, head.dy - 2.8, head.dx - fishLen, head.dy)
        ..quadraticBezierTo(head.dx - fishLen * 0.5, head.dy + 2.4, head.dx, head.dy)
        ..close();
      c.drawPath(body, _fill(const Color(0xFFF29A3E), a));
      c.drawPath(body, _inkA(a, 1.0));
    }
    // Bones show where the fish was eaten.
    final bones = Paint()
      ..color = k.ink.withValues(alpha: 0.8 * a)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final boneEnd = head.dx - 10;
    final boneStart = head.dx - fishLen;
    if (boneStart - boneEnd > 0.5) {
      c.drawLine(Offset(boneEnd, head.dy), Offset(boneStart, head.dy), bones);
      for (var x = boneEnd + 1.2; x < boneStart; x += 1.8) {
        c.drawLine(Offset(x, head.dy - 1.4), Offset(x, head.dy + 1.4), bones);
      }
      c.drawPath(
          Path()
            ..moveTo(boneEnd, head.dy)
            ..lineTo(boneEnd - 2, head.dy - 1.8)
            ..moveTo(boneEnd, head.dy)
            ..lineTo(boneEnd - 2, head.dy + 1.8),
          bones..style = PaintingStyle.stroke);
    }
    if (bite >= 0.95) {
      c.drawCircle(head + const Offset(-1.6, 0), 1.6, _fill(const Color(0xFFF29A3E), a));
      c.drawCircle(head + const Offset(-1.6, 0), 1.6, _inkA(a, 0.8)..style = PaintingStyle.stroke);
    }
    c.drawCircle(head + const Offset(-1.8, -0.6), 0.5, _fill(k.ink, a));
    c.restore();
  }

  /// Litter tray: back wall behind the cat.
  void _litterBack(double a) {
    final back = RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -11, 50, 11), const Radius.circular(2.5));
    c.drawRRect(back, _fill(const Color(0xFF5FA79C), a));
    c.drawRRect(back, _inkA(a));
    c.drawRect(const Rect.fromLTWH(-24, -8.5, 46, 3), _fill(const Color(0xFFE6D29E), a));
  }

  /// Litter tray: front lip in front of the cat.
  void _litterFront(double a) {
    final front = RRect.fromRectAndRadius(const Rect.fromLTWH(-28, -6.5, 54, 6.5), const Radius.circular(2.5));
    c.drawRRect(front, _fill(const Color(0xFF6FBAAE), a));
    c.drawRRect(front, _inkA(a));
  }

  /// Newspaper held open in both paws.
  void _newspaper(double a) {
    final center = Offset.lerp(_nearPaw, _farPaw, 0.5)! + const Offset(1, -6);
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(0.06);
    const rect = Rect.fromLTWH(-12, -8.5, 24, 17);
    c.drawRect(rect, _fill(const Color(0xFFF4F1EA), a));
    c.drawRect(const Rect.fromLTWH(-12, -8.5, 24, 3), _fill(const Color(0xFF3A3A3A), a));
    c.drawLine(const Offset(0, -5.5), const Offset(0, 8.5), Paint()
      ..color = const Color(0xFFCFC8B8).withValues(alpha: a)
      ..strokeWidth = 0.8);
    c.drawRect(const Rect.fromLTWH(-10.5, -4, 9, 5.5), _fill(const Color(0xFFB9C7D6), a));
    final lines = Paint()
      ..color = const Color(0xFF9A948A).withValues(alpha: a)
      ..strokeWidth = 0.8;
    for (var y = -3.5; y < 7.5; y += 1.8) {
      c.drawLine(Offset(1.5, y), const Offset(10.5, 0) + Offset(0, y), lines);
    }
    for (var y = 3.0; y < 7.5; y += 1.8) {
      c.drawLine(Offset(-10.5, y), Offset(-1.5, y), lines);
    }
    c.drawRect(rect, _inkA(a, 1.1)..style = PaintingStyle.stroke);
    c.restore();
    for (final paw in [_nearPaw, _farPaw]) {
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _fill(k.paw, a));
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _inkA(a));
    }
  }

  /// Phone in the near paw, screen lighting the face.
  void _phone(double a) {
    final paw = _nearPaw;
    final glow = Paint()..color = const Color(0xFF9FE0FF).withValues(alpha: 0.18 * a);
    c.drawOval(Rect.fromCenter(center: _hp(9, 2), width: 18, height: 14), glow);
    c.save();
    c.translate(paw.dx + 2, paw.dy - 4);
    c.rotate(-0.45);
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -5, 6, 10), const Radius.circular(1.3));
    c.drawRRect(body, _fill(const Color(0xFF26282E), a));
    c.drawRRect(body, _inkA(a, 1.0));
    const screen = Rect.fromLTWH(-2.2, -4.1, 4.4, 8.2);
    c.drawRect(screen, _fill(const Color(0xFFBFEAFF), a));
    c.save();
    c.clipRect(screen);
    final off = (p[P.scroll] % 1) * 3.2;
    for (var i = -1; i < 5; i++) {
      final y = -4.1 + i * 3.2 - off + 3.2;
      c.drawRect(Rect.fromLTWH(-1.7, y, 1.4, 1.4), _fill(const Color(0xFFF2A65A), a));
      c.drawLine(Offset(0.2, y + 0.4), Offset(1.8, y + 0.4), Paint()
        ..color = const Color(0xFF5E7787).withValues(alpha: a)
        ..strokeWidth = 0.6);
    }
    c.restore();
    c.restore();
    c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _fill(k.paw, a));
    c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _inkA(a));
  }

  /// TV on a low stand, playing a little platform game.
  void _tv(double a) {
    final stand = RRect.fromRectAndRadius(const Rect.fromLTWH(33, -8, 28, 8), const Radius.circular(1.2));
    c.drawRRect(stand, _fill(CatInk.wood, a));
    c.drawRRect(stand, _inkA(a, 1.1));
    final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(32, -33, 30, 23), const Radius.circular(2));
    c.drawRRect(frame, _fill(const Color(0xFF26282E), a));
    c.drawRRect(frame, _inkA(a));
    c.drawRect(const Rect.fromLTWH(45, -10, 4, 2), _fill(const Color(0xFF26282E), a));
    const screen = Rect.fromLTWH(34.2, -31, 25.6, 18.6);
    final win = p[P.win];
    final base = Color.lerp(const Color(0xFF233A5E), win >= 0 ? const Color(0xFFFFD166) : const Color(0xFFD7263D), win.abs() * 0.75)!;
    c.drawRect(screen, _fill(base, a));
    c.save();
    c.clipRect(screen);
    final t = p[P.time];
    // Ground, scrolling blocks and a jumping hero.
    c.drawRect(Rect.fromLTWH(screen.left, screen.bottom - 3, screen.width, 3), _fill(const Color(0xFF3FAE6A), a));
    for (var i = 0; i < 3; i++) {
      final x = screen.right - ((t * 14 + i * 10) % (screen.width + 6));
      c.drawRect(Rect.fromLTWH(x, screen.bottom - 6, 3, 3), _fill(const Color(0xFFF2A65A), a));
    }
    final jump = (math.sin(t * 7)).abs() * 6 * (p[P.mash] > 0 ? 1 : 0.2);
    c.drawRect(Rect.fromLTWH(screen.left + 6, screen.bottom - 7 - jump, 3, 4), _fill(k.scarf, a));
    if (win.abs() > 0.3) {
      for (var i = 0; i < 6; i++) {
        final ang = i * math.pi / 3 + t * 2;
        c.drawCircle(screen.center + Offset(math.cos(ang), math.sin(ang)) * 6, 1.2, _fill(const Color(0xFFFFFFFF), a * win.abs()));
      }
    }
    c.restore();
    // Light from the screen on the floor.
    c.drawOval(Rect.fromCenter(center: const Offset(30, -1), width: 26, height: 4),
        _fill(win >= 0 ? const Color(0xFF9FD3F0) : const Color(0xFFF7A6A0), 0.25 * a));
  }

  /// Gamepad held in both paws; the buttons light up while mashing.
  void _gamepad(double a) {
    final center = Offset.lerp(_nearPaw, _farPaw, 0.5)! + const Offset(1, -2);
    c.save();
    c.translate(center.dx, center.dy);
    final body = Path()
      ..moveTo(-6, -2)
      ..lineTo(6, -2)
      ..quadraticBezierTo(9, -2, 8.5, 2.5)
      ..quadraticBezierTo(7, 4, 4.5, 1.5)
      ..lineTo(-4.5, 1.5)
      ..quadraticBezierTo(-7, 4, -8.5, 2.5)
      ..quadraticBezierTo(-9, -2, -6, -2)
      ..close();
    c.drawPath(body, _fill(const Color(0xFF3A3F47), a));
    c.drawPath(body, _inkA(a, 1.1));
    final m = p[P.mash];
    c.drawCircle(const Offset(4.2, -0.4), 0.9, _fill(Color.lerp(const Color(0xFFD7263D), const Color(0xFFFFE066), m)!, a));
    c.drawCircle(const Offset(5.9, 0.7), 0.9, _fill(Color.lerp(const Color(0xFF2F80C8), const Color(0xFFFFE066), 1 - m)!, a));
    c.drawRect(const Rect.fromLTWH(-5.6, -0.6, 3.2, 1), _fill(const Color(0xFFBFC5CC), a));
    c.drawRect(const Rect.fromLTWH(-4.5, -1.7, 1, 3.2), _fill(const Color(0xFFBFC5CC), a));
    c.restore();
    for (final paw in [_nearPaw, _farPaw]) {
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _fill(k.paw, a));
      c.drawOval(Rect.fromCenter(center: paw, width: 6.2, height: 4.4), _inkA(a));
    }
  }

  // ---- marks (drawn un-mirrored so text reads correctly) ---------------------------

  void _marks() {
    final f = facing;
    Offset world(Offset local) => Offset((local.dx + p[P.rootX]) * f, local.dy + p[P.rootY]);
    final headTop = world(_head + const Offset(2, -27));

    if (p[P.exclaim] > 0.02) _text('!', headTop + const Offset(0, -2), 15, k.scarf, p[P.exclaim]);
    if (p[P.question] > 0.02) {
      final bob = math.sin(p[P.time] * 3 + p[P.headRot] * 4) * 1.5;
      _text('?', headTop + Offset(6 * f, -2 + bob), 15, k.ink, p[P.question]);
    }
    if (p[P.sweat] > 0.02) {
      final at = world(_head + const Offset(-12, -10));
      final a = p[P.sweat].clamp(0.0, 1.0);
      final drop = Path()
        ..moveTo(at.dx, at.dy - 4)
        ..quadraticBezierTo(at.dx + 3, at.dy + 1, at.dx, at.dy + 2)
        ..quadraticBezierTo(at.dx - 3, at.dy + 1, at.dx, at.dy - 4)
        ..close();
      c.drawPath(drop, _fill(const Color(0xFF7CC4E8), a));
      c.drawPath(drop, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 0.9);
    }
    final impact = p[P.impact].clamp(0.0, 1.0);
    if (impact > 0.02) {
      final office = p[P.office] > 0.5;
      final at = office ? Offset(37.5 * f, -42) : world(_head + const Offset(14, -6));
      _burst(at, 5 + 6 * impact, impact);
      if (office && impact > 0.3) {
        _text('ENTER', Offset(at.dx + 2 * f, at.dy - 13), 7.5, k.scarf, impact, bold: true, box: true);
      }
    }
    if (p[P.notes] > 0.02) {
      final a = p[P.notes].clamp(0.0, 1.5);
      final t = p[P.time];
      const cols = [Color(0xFF6C63FF), Color(0xFFD7263D), Color(0xFF2FBF8F)];
      for (var i = 0; i < 3; i++) {
        final u = ((t * 0.5 + i / 3) % 1);
        final sway = math.sin(u * math.pi * 2 + i) * 3;
        final at = world(_head + Offset(9 + i * 3 + sway, -16 - u * 22));
        _note(at, 0.75 + u * 0.5, cols[i], a.clamp(0.0, 1.0) * math.sin(math.pi * u), i.isOdd);
      }
    }
    if (p[P.say] > 0.02) {
      final i = p[P.sayKind].round().clamp(0, homeSayings.length - 1);
      final at = headTop + Offset(16 * f, -2);
      _text(homeSayings[i], at, 7.5, k.ink, p[P.say], box: true);
    }
    if (p[P.stink] > 0.02) {
      final a = p[P.stink].clamp(0.0, 1.0);
      final t = p[P.time];
      final sp = Paint()
        ..color = const Color(0xFF8DB84A).withValues(alpha: 0.8 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final u = ((t * 0.4 + i / 3) % 1);
        final x0 = (-18.0 + i * 7) * f;
        final y0 = -10.0 - u * 16;
        final path = Path()..moveTo(x0, y0);
        for (var j = 1; j <= 4; j++) {
          path.lineTo(x0 + math.sin(t * 3 + j + i) * 1.6, y0 - j * 2.6);
        }
        c.drawPath(path, sp..color = const Color(0xFF8DB84A).withValues(alpha: 0.8 * a * math.sin(math.pi * u)));
      }
    }
    if (p[P.zzz] > 0.02) {
      final a = p[P.zzz].clamp(0.0, 1.0);
      final t = p[P.time];
      for (var i = 0; i < 3; i++) {
        final u = ((t * 0.45 + i / 3) % 1);
        final at = world(_head + Offset(8 + u * 10 + i * 2, -14 - u * 16));
        _text('z', at, 6 + u * 6, CatInk.kantha, a * math.sin(math.pi * u), bold: true);
      }
    }
    if (p[P.dream] > 0.02) {
      final a = p[P.dream].clamp(0.0, 1.0);
      final at = world(_head + const Offset(-6, -30));
      c.drawCircle(world(_head + const Offset(3, -15)), 1.4, _fill(const Color(0xFFFFFFFF), a));
      c.drawCircle(world(_head + const Offset(0, -20)), 2.2, _fill(const Color(0xFFFFFFFF), a));
      final cloud = _ellipse(at, 11, 7, 0, n: 10, jitter: 0.5);
      _shape(cloud, const Color(0xFFFFFFFF), a);
      if (p[P.dreamKind] < 0.5) {
        _fishCursor(at + const Offset(1, 0), a);
      } else {
        // A tiny cha glass with a heart.
        final g = Path()
          ..moveTo(at.dx - 3, at.dy - 3.5)
          ..lineTo(at.dx + 3, at.dy - 3.5)
          ..lineTo(at.dx + 2.2, at.dy + 3.5)
          ..lineTo(at.dx - 2.2, at.dy + 3.5)
          ..close();
        c.drawPath(g, _fill(CatInk.tea, a));
        c.drawPath(g, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 0.9);
        _text('♥', at + const Offset(6.5, -3), 6, k.scarf, a);
      }
    }
  }

  /// A drawn music note (no font needed): head, stem and a flag or beam.
  void _note(Offset at, double sc, Color col, double a, bool beamed) {
    if (a <= 0.02) return;
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(sc);
    final fill = _fill(col, a);
    final line = Paint()
      ..color = col.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    c.drawOval(Rect.fromCenter(center: const Offset(0, 0), width: 4.2, height: 3.0), fill);
    c.drawLine(const Offset(1.9, -0.4), const Offset(1.9, -8), line);
    if (beamed) {
      c.drawOval(Rect.fromCenter(center: const Offset(6, -1), width: 4.2, height: 3.0), fill);
      c.drawLine(const Offset(7.9, -1.4), const Offset(7.9, -9), line);
      c.drawLine(const Offset(1.9, -8), const Offset(7.9, -9), line..strokeWidth = 2.0);
    } else {
      c.drawPath(
          Path()
            ..moveTo(1.9, -8)
            ..quadraticBezierTo(5.5, -6.5, 4.5, -2.5)
            ..quadraticBezierTo(4.6, -5.2, 1.9, -5.6)
            ..close(),
          fill);
    }
    c.restore();
  }

  void _burst(Offset at, double r, double a) {
    final path = Path();
    for (var i = 0; i < 16; i++) {
      final ang = 2 * math.pi * i / 16;
      final rr = i.isEven ? r : r * 0.5;
      final pt = at + Offset(math.cos(ang), math.sin(ang)) * rr;
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    c.drawPath(path, _fill(const Color(0xFFFFE066), a));
    c.drawPath(path, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.0);
  }

  void _text(String s, Offset at, double size, Color col, double a, {bool bold = true, bool box = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          color: col.withValues(alpha: a.clamp(0.0, 1.0)),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = at - Offset(tp.width / 2, tp.height / 2);
    if (box) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx - 2, o.dy - 1.5, tp.width + 4, tp.height + 3), const Radius.circular(2));
      c.drawRRect(r, _fill(const Color(0xFFFFFFFF), a));
      c.drawRRect(r, _ink..color = k.ink.withValues(alpha: a)..strokeWidth = 1.0);
    }
    tp.paint(c, o);
  }
}

/// Renders a single pose to an image (used by the comic and tests).
Future<ui.Image> renderPose(Pose pose, double width, {CatSkin? skin}) async {
  final recorder = ui.PictureRecorder();
  final h = width * CatCanvas.height / CatCanvas.width;
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, h));
  CatPainter(pose, skin: skin).paint(canvas, Size(width, h));
  return recorder.endRecording().toImage(width.ceil(), h.ceil());
}
