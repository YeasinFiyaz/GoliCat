import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../cat/cat_layer.dart';
import '../demo/demo_map.dart';
import '../demo/demo_script.dart';
import '../places/place_store.dart';
import '../tracking/roam_session.dart';
import 'comic_screen.dart';
import 'theme.dart';

/// Simulated outing: no location access, no Google Maps key, nothing saved.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, required this.store, this.startAt});
  final AppStore store;
  final double? startAt;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> with SingleTickerProviderStateMixin {
  final script = DemoScript();
  final cam = DemoProjector();
  late RoamSession session;
  double simT = 0;
  int _fixIdx = 0;
  bool playing = true;
  double speed = 4;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _reset(widget.startAt ?? 0);
    _ticker = createTicker(_tick)..start();
  }

  DateTime _clock() => DemoScript.epoch.add(Duration(milliseconds: (simT * 1000).round()));

  RoamSession _newSession() => RoamSession(
        clock: _clock,
        office: DemoScript.office,
        home: DemoScript.home,
        demo: true,
        reducedMotion: widget.store.reducedMotion,
      );

  /// Restart and fast-forward the simulation to [t] seconds.
  void _reset(double t) {
    simT = 0;
    _fixIdx = 0;
    session = _newSession();
    for (var s = 0.0; s <= t; s += 1) {
      simT = s;
      _feed();
      session.evaluate();
    }
    simT = t;
    final mode = session.snap?.mode;
    if (mode != null) session.director.snapTo(mode);
    final p = session.snap?.position;
    if (p != null) {
      session.position.reset();
      session.position.target(p, _clock());
      cam.snap(p);
    }
  }

  void _feed() {
    final now = _clock();
    while (_fixIdx < script.fixes.length && !script.fixes[_fixIdx].time.isAfter(now)) {
      session.engine.addFix(script.fixes[_fixIdx++]);
    }
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.1) dt = 0.1;
    if (playing && simT < DemoScript.duration) {
      simT = (simT + dt * speed).clamp(0, DemoScript.duration);
      _feed();
      session.evaluate();
    }
    final p = session.position.shown;
    if (p != null) cam.follow(p, dt);
    _repaint.value++;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String get _clockText {
    final t = _clock();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  void _endTrip() {
    final log = session.finish();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComicScreen(log: log)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        cam.size = Size(box.maxWidth, box.maxHeight);
        cam.bottomInset = 230;
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: DemoMapPainter(cam, repaint: _repaint))),
          Positioned.fill(
            child: CatLayer(
              session: session,
              projector: cam,
              scale: widget.store.catScale * 1.15,
              timeScale: speed,
              reducedMotion: widget.store.reducedMotion,
            ),
          ),
          // Clear "demo" labelling.
          Positioned(
            top: mq.padding.top + 8,
            left: 8,
            right: 12,
            child: Row(children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to the real map',
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: GoliTheme.ink, borderRadius: BorderRadius.circular(20)),
                  child: const Text('DEMO MAP · simulated, not real streets',
                      maxLines: 2,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            ]),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: mq.padding.bottom + 10,
            child: Material(
              elevation: 6,
              color: GoliTheme.paper,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(session.director.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Text(_clockText, style: t.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                  Text(_hint(), style: t.bodySmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                      for (final (name, at) in DemoScript.scenes)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(name),
                            onPressed: () => setState(() => _reset(at)),
                          ),
                        ),
                    ])),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    IconButton.filled(
                      onPressed: () => setState(() {
                        if (simT >= DemoScript.duration) _reset(0);
                        playing = !playing;
                      }),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      tooltip: playing ? 'Pause' : 'Play',
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SegmentedButton<double>(
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1×')),
                        ButtonSegment(value: 4, label: Text('4×')),
                        ButtonSegment(value: 16, label: Text('16×')),
                      ],
                      selected: {speed},
                      onSelectionChanged: (v) => setState(() => speed = v.first),
                    ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(onPressed: _endTrip, child: const Text('End trip')),
                  ]),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  String _hint() {
    switch (session.director.clip.name) {
      case 'typing':
        return 'Tap the cat for a surprise. Watch for the Enter key.';
      case 'idle':
      case 'tea':
        return 'Tap the cat: it bats at its own pin.';
      case 'sleep':
        return 'Tap the cat… if you dare.';
      default:
        return 'Simulated time runs ${speed.round()}× faster. Jump to a scene below.';
    }
  }
}
