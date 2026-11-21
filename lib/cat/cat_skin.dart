import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Extra costume details the painter draws on top of the colours.
enum HeroLook { none, bat, superman, spider, catwoman, iron, wonder }

/// One avatar: the same cat and the same animations, in different colours.
class CatSkin {
  CatSkin({
    required this.id,
    required this.name,
    required this.blurb,
    required this.badge,
    required this.fur,
    required this.patch,
    required this.scarf,
    required this.scarfDark,
    this.ink = const Color(0xFF4A2A20),
    this.look = HeroLook.none,
    this.earPink = const Color(0xFFF7B6A8),
    this.blush = const Color(0xFFF7A6A0),
    this.nose = const Color(0xFFE08A8A),
    this.eyeOutline = false,
    Color? body,
    Color? bodyFar,
    Color? bodyPatch,
    Color? muzzle,
    Color? belly,
    Color? paw,
    Color? eye,
  })  : body = body ?? fur,
        bodyPatch = bodyPatch ?? patch,
        muzzle = muzzle ?? Color.lerp(fur, const Color(0xFFFFFFFF), 0.55)!,
        eye = eye ?? ink,
        bodyFar = bodyFar ?? Color.lerp(body ?? fur, ink, 0.14)!,
        belly = belly ?? muzzle ?? Color.lerp(body ?? fur, const Color(0xFFFFFFFF), 0.55)!,
        paw = paw ?? muzzle ?? Color.lerp(body ?? fur, const Color(0xFFFFFFFF), 0.55)!;

  /// Saved in preferences; never change an id once released.
  final String id;
  final String name;
  final String blurb;
  final HeroLook look;

  /// Soft circle behind the cat in the picker.
  final Color badge;

  /// Outline colour.
  final Color ink;

  /// Head fur, and the patch on top of the head.
  final Color fur, patch;

  /// Body, legs and tail; the far-side legs; the patch on the back and tail.
  final Color body, bodyFar, bodyPatch;

  final Color muzzle, belly, paw;
  final Color earPink, blush, nose;
  final Color scarf, scarfDark;

  /// Eye colour (white for masked cats), with an outline for big mask eyes.
  final Color eye;
  final bool eyeOutline;

  bool get isHero => look != HeroLook.none;

  static final CatSkin original = CatSkin(
    id: 'goli',
    name: 'Goli',
    blurb: 'The original street cat',
    badge: const Color(0xFFFBF6EE),
    fur: const Color(0xFFFFFFFF),
    patch: const Color(0xFFF2A65A),
    muzzle: const Color(0xFFFBEFD9),
    bodyFar: const Color(0xFFEDE4D8),
    scarf: const Color(0xFFD7263D),
    scarfDark: const Color(0xFF9C1A2D),
  );

  static final List<CatSkin> all = [
    original,
    CatSkin(
      id: 'ginger',
      name: 'Komola',
      blurb: 'Sweet as an orange',
      badge: const Color(0xFFE3F5F1),
      fur: const Color(0xFFF6A04D),
      patch: const Color(0xFFFFE2B8),
      earPink: const Color(0xFFFFD0B0),
      blush: const Color(0xFFF2766B),
      scarf: const Color(0xFF1FA89A),
      scarfDark: const Color(0xFF147A70),
    ),
    CatSkin(
      id: 'grey',
      name: 'Megh',
      blurb: 'A little rain cloud',
      badge: const Color(0xFFFFF6D9),
      ink: const Color(0xFF3A3340),
      fur: const Color(0xFFAEB5BF),
      patch: const Color(0xFFFFFFFF),
      scarf: const Color(0xFFF7C331),
      scarfDark: const Color(0xFFC9951A),
    ),
    CatSkin(
      id: 'black',
      name: 'Kajol',
      blurb: 'Dark as kohl, soft as night',
      badge: const Color(0xFFFFE3E3),
      ink: const Color(0xFF1E1A22),
      fur: const Color(0xFF443E4A),
      patch: const Color(0xFFFFFFFF),
      muzzle: const Color(0xFFF1ECEF),
      earPink: const Color(0xFFF29AA8),
      blush: const Color(0xFFF28A9A),
      eye: const Color(0xFFFFFFFF),
      scarf: const Color(0xFFD7263D),
      scarfDark: const Color(0xFF9C1A2D),
    ),
    CatSkin(
      id: 'siamese',
      name: 'Chini',
      blurb: 'Sugar with a cocoa cap',
      badge: const Color(0xFFE1ECFF),
      fur: const Color(0xFFF3E3CC),
      patch: const Color(0xFF8A5A44),
      earPink: const Color(0xFFD9A08A),
      scarf: const Color(0xFF2F6FDB),
      scarfDark: const Color(0xFF1F4FA3),
    ),
    CatSkin(
      id: 'pink',
      name: 'Golapi',
      blurb: 'Rosy and proud of it',
      badge: const Color(0xFFF1E8FF),
      ink: const Color(0xFF5A2340),
      fur: const Color(0xFFFFC6DA),
      patch: const Color(0xFFFF8FB3),
      earPink: const Color(0xFFFF8FB3),
      blush: const Color(0xFFFF6F9C),
      scarf: const Color(0xFF7C4DDB),
      scarfDark: const Color(0xFF5632A3),
    ),
    CatSkin(
      id: 'sky',
      name: 'Neelu',
      blurb: 'A piece of blue sky',
      badge: const Color(0xFFFFEEDD),
      ink: const Color(0xFF24405C),
      fur: const Color(0xFFAEDBF7),
      patch: const Color(0xFF5BAEE6),
      earPink: const Color(0xFFF7B6C8),
      blush: const Color(0xFFF7A6C0),
      scarf: const Color(0xFFFF8A3D),
      scarfDark: const Color(0xFFC9601A),
    ),
    CatSkin(
      id: 'mint',
      name: 'Pudina',
      blurb: 'Fresh as a mint leaf',
      badge: const Color(0xFFFFE6EF),
      ink: const Color(0xFF1F4A3A),
      fur: const Color(0xFFB9EDCF),
      patch: const Color(0xFF5CC98F),
      scarf: const Color(0xFFF0508A),
      scarfDark: const Color(0xFFB8305F),
    ),
    CatSkin(
      id: 'lavender',
      name: 'Beguni',
      blurb: 'Dreamy purple fluff',
      badge: const Color(0xFFE2F8EF),
      ink: const Color(0xFF3A2A66),
      fur: const Color(0xFFD9CBF8),
      patch: const Color(0xFF9C7FE8),
      earPink: const Color(0xFFF7B6D8),
      blush: const Color(0xFFF79AC0),
      scarf: const Color(0xFF2FBF8F),
      scarfDark: const Color(0xFF1E8C68),
    ),
    CatSkin(
      id: 'chocolate',
      name: 'Choco',
      blurb: 'Melts in the sun',
      badge: const Color(0xFFF1F7DD),
      ink: const Color(0xFF3A1F14),
      fur: const Color(0xFFB57C55),
      patch: const Color(0xFFF3D9B8),
      muzzle: const Color(0xFFF3D9B8),
      earPink: const Color(0xFFF3B9A0),
      blush: const Color(0xFFF08A78),
      scarf: const Color(0xFF9BCB3C),
      scarfDark: const Color(0xFF6E9624),
    ),
    CatSkin(
      id: 'golden',
      name: 'Shona',
      blurb: 'Pure gold, pure trouble',
      badge: const Color(0xFFE3E7FB),
      fur: const Color(0xFFFFDB6E),
      patch: const Color(0xFFFF9F1C),
      earPink: const Color(0xFFFFB38A),
      blush: const Color(0xFFF7907A),
      scarf: const Color(0xFF2B3A8C),
      scarfDark: const Color(0xFF1B255E),
    ),
    // ---- hero cats ----------------------------------------------------------
    CatSkin(
      id: 'batcat',
      name: 'Batcat',
      blurb: 'Guards the alley at night',
      look: HeroLook.bat,
      badge: const Color(0xFFDDE3F0),
      ink: const Color(0xFF1A1B24),
      fur: const Color(0xFF2F3242),
      patch: const Color(0xFF474B60),
      muzzle: const Color(0xFFF3E3CC),
      belly: const Color(0xFF474B60),
      paw: const Color(0xFF474B60),
      earPink: const Color(0xFF474B60),
      eye: const Color(0xFFFFFFFF),
      scarf: const Color(0xFFF7C331),
      scarfDark: const Color(0xFFC9951A),
    ),
    CatSkin(
      id: 'supermancat',
      name: 'Supermancat',
      blurb: 'Faster than a rickshaw',
      look: HeroLook.superman,
      badge: const Color(0xFFDCEBFF),
      ink: const Color(0xFF3A2418),
      fur: const Color(0xFFF6DFC6),
      patch: const Color(0xFF23232E),
      muzzle: const Color(0xFFFBEFE0),
      body: const Color(0xFF2F6FDB),
      bodyPatch: const Color(0xFFD7263D),
      belly: const Color(0xFFF7C331),
      paw: const Color(0xFFD7263D),
      scarf: const Color(0xFFD7263D),
      scarfDark: const Color(0xFF9C1A2D),
    ),
    CatSkin(
      id: 'spidercat',
      name: 'Spidercat',
      blurb: 'Your friendly neighbourhood cat',
      look: HeroLook.spider,
      badge: const Color(0xFFDCE6FF),
      ink: const Color(0xFF3A0E18),
      fur: const Color(0xFFDD2B3F),
      patch: const Color(0xFFDD2B3F),
      muzzle: const Color(0xFFDD2B3F),
      body: const Color(0xFF2F5FD0),
      bodyPatch: const Color(0xFFDD2B3F),
      belly: const Color(0xFFDD2B3F),
      paw: const Color(0xFFDD2B3F),
      earPink: const Color(0xFFA8182A),
      blush: const Color(0x00DD2B3F),
      nose: const Color(0xFF8E1424),
      eye: const Color(0xFFFFFFFF),
      eyeOutline: true,
      scarf: const Color(0xFF2F5FD0),
      scarfDark: const Color(0xFF1F3F96),
    ),
    CatSkin(
      id: 'catwoman',
      name: 'Catwoman',
      blurb: 'Nine lives, zero rules',
      look: HeroLook.catwoman,
      badge: const Color(0xFFEBDDF7),
      ink: const Color(0xFF17141C),
      fur: const Color(0xFF2A2630),
      patch: const Color(0xFF3F3948),
      muzzle: const Color(0xFFF6DDC8),
      belly: const Color(0xFF3F3948),
      paw: const Color(0xFF3F3948),
      earPink: const Color(0xFF4A4454),
      blush: const Color(0xFFF28A9A),
      eye: const Color(0xFFFFFFFF),
      scarf: const Color(0xFF8A45C8),
      scarfDark: const Color(0xFF5F2C90),
    ),
    CatSkin(
      id: 'ironmancat',
      name: 'Ironmancat',
      blurb: 'Built it in a tea stall',
      look: HeroLook.iron,
      badge: const Color(0xFFFFE9C9),
      ink: const Color(0xFF3A0E12),
      fur: const Color(0xFFC81E2B),
      patch: const Color(0xFFE0343F),
      muzzle: const Color(0xFFF2B632),
      bodyPatch: const Color(0xFFF2B632),
      belly: const Color(0xFFF2B632),
      paw: const Color(0xFFF2B632),
      earPink: const Color(0xFFF2B632),
      blush: const Color(0x00C81E2B),
      nose: const Color(0xFFB9831A),
      eye: const Color(0xFFBDF3FF),
      eyeOutline: true,
      scarf: const Color(0xFFF2B632),
      scarfDark: const Color(0xFFB9831A),
    ),
    CatSkin(
      id: 'wonderwomancat',
      name: 'Wonderwomancat',
      blurb: 'Brave heart, golden crown',
      look: HeroLook.wonder,
      badge: const Color(0xFFDCE6FF),
      ink: const Color(0xFF3A2418),
      fur: const Color(0xFFF6DDC8),
      patch: const Color(0xFF23202B),
      muzzle: const Color(0xFFFBEFE0),
      body: const Color(0xFFD7263D),
      bodyPatch: const Color(0xFF2F4FB8),
      belly: const Color(0xFFF2B632),
      paw: const Color(0xFFF2B632),
      scarf: const Color(0xFFD7263D),
      scarfDark: const Color(0xFFF2B632),
    ),
  ];

  /// Unknown or missing ids fall back to the original cat.
  static CatSkin byId(String? id) => all.firstWhere((s) => s.id == id, orElse: () => original);
}

/// The avatar the user picked. Every cat drawn in the app uses this one, so
/// changing it changes the map and the comic together.
final ValueNotifier<CatSkin> activeCatSkin = ValueNotifier<CatSkin>(CatSkin.original);
