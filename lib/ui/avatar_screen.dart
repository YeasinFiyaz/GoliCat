import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../cat/cat_painter.dart';
import '../cat/cat_skin.dart';
import '../cat/clips.dart';
import '../places/place_store.dart';
import 'theme.dart';

/// Pick which cat walks with you. The choice is saved on this phone and used
/// everywhere a cat is drawn: the map, the comic and live shares.
class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Seconds since the screen opened; drives the walking preview only.
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6);
    if (!widget.store.reducedMotion) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _pick(CatSkin skin) => setState(() => widget.store.catSkinId = skin.id);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final current = CatSkin.byId(widget.store.catSkinId);
    final street = CatSkin.all.where((s) => !s.isHero).toList();
    final heroes = CatSkin.all.where((s) => s.isHero).toList();

    Widget header(String text) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(text, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        );

    Widget grid(List<CatSkin> skins) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 132,
              mainAxisExtent: 186,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _AvatarTile(
                key: ValueKey('avatar_${skins[i].id}'),
                skin: skins[i],
                selected: skins[i].id == current.id,
                onTap: () => _pick(skins[i]),
              ),
              childCount: skins.length,
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Choose your cat')),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: BoxDecoration(
                  color: current.badge,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GoliTheme.ink.withValues(alpha: 0.12)),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    height: 150 * CatCanvas.height / CatCanvas.width,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (context, time, _) => CustomPaint(
                        painter: CatPainter(
                          sampleClip(ClipId.walk, time, ClipCtx(time: time)),
                          boil: (time * 7).floor(),
                          skin: current,
                          reducedMotion: widget.store.reducedMotion,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Walking with you', style: t.labelMedium),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(current.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(height: 2),
                      Text(current.blurb, style: t.bodyMedium),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          header('Street cats'),
          grid(street),
          header('Hero cats'),
          grid(heroes),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Text('Your cat shows on your map, in your comics and to anyone you share a live link with.'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({super.key, required this.skin, required this.selected, required this.onTap});
  final CatSkin skin;
  final bool selected;
  final VoidCallback onTap;

  /// One fixed, calm pose for every tile so the cats are easy to compare.
  static final _pose = sampleClip(ClipId.idle, 0.4, const ClipCtx(time: 0.4));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true, // one spoken label, not name + blurb twice
      label: '${skin.name}. ${skin.blurb}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: skin.badge,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? GoliTheme.red : GoliTheme.ink.withValues(alpha: 0.12),
                    width: selected ? 3.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 98,
                  height: 98 * CatCanvas.height / CatCanvas.width,
                  child: RepaintBoundary(child: CustomPaint(painter: CatPainter(_pose, skin: skin))),
                ),
              ),
              if (selected)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle, color: GoliTheme.red, size: 26),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(skin.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(
              skin.blurb,
              style: t.bodySmall?.copyWith(fontSize: 11, height: 1.15),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ),
    );
  }
}
