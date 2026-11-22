import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/geo.dart';
import 'cat_source.dart';
import 'cat_painter.dart';

/// Converts coordinates to on-screen positions for whatever map is beneath.
abstract class MapProjector {
  Offset? toScreen(GeoPoint p);
  double get bearingDeg;
}

/// Draws GoliCat over the map at the session's (glided) position, every frame.
class CatLayer extends StatefulWidget {
  const CatLayer({
    super.key,
    required this.session,
    required this.projector,
    required this.scale,
    this.timeScale = 1,
    this.reducedMotion = false,
    this.onFrame,
  });

  final CatSource session;
  final MapProjector projector;
  final double scale;

  /// Time multiplier for position glides (1 = real time).
  final double timeScale;
  final bool reducedMotion;
  final VoidCallback? onFrame;

  @override
  State<CatLayer> createState() => _CatLayerState();
}

class _CatLayerState extends State<CatLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _boil = 0;
  double _boilAcc = 0;

  /// Time not yet drawn while frames are being skipped.
  double _pending = 0;

  /// A settled cat is drawn at this rate; anything lively gets every frame.
  static const _calmFrame = 1 / 30;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.1) dt = 0.1;
    final s = widget.session;
    // Battery: asleep or sipping cha, half the frames look identical. Skip
    // them (the map itself still pans at full rate: it repaints on its own).
    _pending += dt;
    if (s.director.calm && !s.moving && !s.position.gliding && _pending < _calmFrame - 0.004) return;
    dt = _pending > 0.1 ? 0.1 : _pending;
    _pending = 0;
    s.director.reducedMotion = widget.reducedMotion;
    s.position.advance(dt * widget.timeScale);
    // Face the direction of travel as seen on screen (map may be rotated).
    if (s.moving) {
      final rel = (s.headingDeg - widget.projector.bearingDeg) * math.pi / 180;
      s.director.setScreenHeading(math.sin(rel));
    }
    s.director.update(dt);
    _boilAcc += dt;
    if (_boilAcc > 1 / 7) {
      _boilAcc = 0;
      _boil++;
    }
    widget.onFrame?.call();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.session.position.shown;
    if (p == null) return const SizedBox.shrink();
    final at = widget.projector.toScreen(p);
    if (at == null) return const SizedBox.shrink();
    final unit = widget.scale;
    final w = CatCanvas.width * unit, h = CatCanvas.height * unit;
    final left = at.dx - CatCanvas.originX * unit, top = at.dy - CatCanvas.originY * unit;
    return Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: CatPainter(widget.session.director.pose,
                  boil: _boil, reducedMotion: widget.reducedMotion),
            ),
          ),
        ),
      ),
      // Tap target over the cat's body only, so the map stays draggable around it.
      Positioned(
        left: at.dx - 32 * unit,
        top: at.dy - 64 * unit,
        width: 64 * unit,
        height: 66 * unit,
        child: Semantics(
          button: true,
          label: 'GoliCat: ${widget.session.director.label}. Tap to play.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.session.director.tap(),
          ),
        ),
      ),
    ]);
  }
}
