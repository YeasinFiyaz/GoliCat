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

  /// Demo fast-forward: position glides use simulated seconds.
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
