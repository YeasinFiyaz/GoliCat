import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../cat/cat_painter.dart';
import '../cat/clips.dart';
import '../cat/pose.dart';
import '../tracking/trip_recorder.dart';
import 'theme.dart';

/// The three-panel end-of-trip comic. Contains no map, route, coordinates or
/// address: only the cat, captions, date, duration and distance.
class ComicScreen extends StatefulWidget {
  const ComicScreen({super.key, required this.log});
  final TripLog log;

  @override
  State<ComicScreen> createState() => _ComicScreenState();
}

class _ComicScreenState extends State<ComicScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<Uint8List?> _png() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bytes = await _png();
      if (bytes == null) return;
      if (!await Gal.hasPermission(toAlbum: true)) await Gal.requestPermission(toAlbum: true);
      await Gal.putImageBytes(bytes, album: 'GoliCat', name: 'golicat_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to your gallery (GoliCat album).')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t save: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = await _png();
    if (bytes == null) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: 'golicat_comic.png')],
      text: 'GoliCat\'s outing',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final panels = comicFor(log);
    final end = log.endedAt ?? DateTime.now();
    final mins = end.difference(log.startedAt).inMinutes;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final date = '${log.startedAt.day} ${months[log.startedAt.month - 1]}';
    final dist = log.distanceM >= 1000
        ? '${(log.distanceM / 1000).toStringAsFixed(1)} km'
        : '${(log.distanceM / 10).round() * 10} m';
    final subtitle = [
      if (log.demo) 'Demo trip',
      date,
      mins < 1 ? 'under a minute' : '$mins min',
      if (log.distanceM > 20) dist,
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('Trip comic'), backgroundColor: GoliTheme.paper),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _key,
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    color: const Color(0xFFFFFBF2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('GoliCat\'s outing',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: GoliTheme.ink)),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF7A6A5C))),
                      const SizedBox(height: 10),
                      for (var i = 0; i < panels.length; i++) ...[
                        _Panel(panel: panels[i], index: i),
                        const SizedBox(height: 10),
                      ],
                      const Text('গলির বিড়াল · made on my phone',
                          textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Color(0xFF9A8A7C))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.download),
                  label: const Text('Save image'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No map, route or address is included in the image.', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.panel, required this.index});
  final ComicPanel panel;
  final int index;

  static const _bgs = [Color(0xFFFFE7C2), Color(0xFFE2F0E4), Color(0xFFE3E7F5)];
  static const _titles = ['Off we go', 'The best bit', 'And then…'];

  @override
  Widget build(BuildContext context) {
    final pose = sampleClip(panel.clip, panel.t, ClipCtx(time: panel.t + 1.3));
    final office = pose[P.office] > 0.5;
    return Container(
      height: 214,
      decoration: BoxDecoration(
        color: _bgs[index % 3],
        border: Border.all(color: GoliTheme.ink, width: 2.5),
      ),
      child: Stack(children: [
        // Ground line.
        Positioned(left: 0, right: 0, bottom: 44, child: Container(height: 2, color: const Color(0x332E221B))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 38,
          child: Center(
            child: SizedBox(
              width: office ? 230 : 200,
              height: (office ? 230 : 200) * CatCanvas.height / CatCanvas.width,
              child: CustomPaint(painter: CatPainter(pose)),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: GoliTheme.ink,
            child: Text(_titles[index],
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: GoliTheme.ink, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(panel.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GoliTheme.ink)),
          ),
        ),
      ]),
    );
  }
}
