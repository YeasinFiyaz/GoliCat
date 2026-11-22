import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'cat/cat_director.dart';
import 'cat/cat_painter.dart';
import 'cat/cat_skin.dart';
import 'tracking/activity_engine.dart';
import 'ui/theme.dart';

/// Animation preview for the desk: the real cat, driven by the real director,
/// so every transition looks exactly as it does in the app.
/// Run:   flutter build web -t lib/preview_main.dart -o build/preview
void main() => runApp(MaterialApp(
      title: 'GoliCat · animation preview',
      debugShowCheckedModeBanner: false,
      theme: GoliTheme.light(),
      home: const PreviewScreen(),
    ));

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> with SingleTickerProviderStateMixin {
  static const _modes = <(String, CatMode)>[
    ('Standing', CatMode.idle),
    ('Walking', CatMode.walking),
    ('Running', CatMode.fast),
    ('Cha break', CatMode.waiting),
    ('At home', CatMode.atHome),
    ('At work', CatMode.atWork),
    ('Studying', CatMode.studying),
    ('Hangout', CatMode.hangingOut),
    ('Traffic jam', CatMode.jammed),
    ('Lost signal', CatMode.lost),
  ];

  /// Minutes added to the real clock, so "Next home activity" can skip ahead.
  int _skipMinutes = 0;
  late final CatDirector _director =
      CatDirector(clock: () => DateTime.now().add(Duration(minutes: _skipMinutes)));
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _speed = 1;
  bool _slowMotion = false;
  CatSkin _skin = CatSkin.original;

  @override
  void initState() {
    super.initState();
    _director.snapTo(CatMode.idle);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    _director.update(dt * (_slowMotion ? 0.25 : _speed));
    setState(() {});
  }

  /// Skips to a daytime minute whose activity differs from the current one.
  void _nextHomeActivity() {
    final now = DateTime.now();
    for (var i = 1; i < 24 * 60; i++) {
      final t = now.add(Duration(minutes: _skipMinutes + i));
      if (CatDirector.homeActivityAt(t) != _director.clip) {
        _skipMinutes += i;
        _director.skipHomeStay();
        break;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final home = _director.mode == CatMode.atHome;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('GoliCat · animation preview', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('The same cat and the same transitions as the app. Tap the cat to poke it.', style: t.bodyMedium),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _director.tap,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EFE6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x22000000)),
                  ),
                  child: AspectRatio(
                    aspectRatio: 2.1,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: CatCanvas.width / CatCanvas.height,
                        child: CustomPaint(painter: CatPainter(_director.pose, skin: _skin)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('${_director.label}   ·   ${_director.clip.name}', style: t.titleMedium),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (name, mode) in _modes)
                  ChoiceChip(
                    label: Text(name),
                    selected: _director.mode == mode,
                    onSelected: (_) => setState(() => _director.setMode(mode)),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.tonalIcon(
                  onPressed: home ? () => setState(_nextHomeActivity) : null,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Next home activity'),
                ),
                FilterChip(
                  label: const Text('Slow motion'),
                  selected: _slowMotion,
                  onSelected: (v) => setState(() => _slowMotion = v),
                ),
                DropdownButton<CatSkin>(
                  value: _skin,
                  items: [for (final s in CatSkin.all) DropdownMenuItem(value: s, child: Text(s.name))],
                  onChanged: (s) => setState(() => _skin = s ?? _skin),
                ),
                SizedBox(
                  width: 260,
                  child: Row(children: [
                    const Text('Speed'),
                    Expanded(
                      child: Slider(
                        value: _speed,
                        min: 0.25,
                        max: 2,
                        divisions: 7,
                        label: '${_speed}x',
                        onChanged: _slowMotion ? null : (v) => setState(() => _speed = v),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                'At home the cat changes activity about once a minute (and sleeps 11 PM to 7 AM). '
                'Use "Next home activity" to skip ahead.',
                style: t.bodySmall,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
