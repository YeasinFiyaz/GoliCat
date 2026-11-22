import 'dart:math' as math;

import 'pose.dart';

/// Context for sampling a clip.
class ClipCtx {
  const ClipCtx({this.amp = 1, this.cadence = 1, this.time = 0});

  /// Motion amplitude: 1 normally, smaller with reduced motion.
  final double amp;

  /// Walk/run cadence multiplier from real speed.
  final double cadence;

  /// Global seconds (for blinks, steam, scarf flutter).
  final double time;
}

enum ClipId {
  idle, walk, fast, skid, batPin,
  sitDown, tea, stashTea, catchUp,
  unfoldMap, lost, foldMap,
  hopOnChair, typing, fishGag, leaveOffice,
  tuckIn, sleep, grumpy, wakeUp,
  sitAtDesk, study, stuckGag, closeBook,
  headphonesOn, vibe, danceGag, headphonesOff,
  jamOn, jam, jamDance, jamOff,
  // Home life: one activity at a time, about a minute each, in a shuffled order.
  homeStroll, homeWake, tuckInHome, leaveHome,
  bath, eat, potty, lounge, gaming,
  // Pins from "More places".
  bazar, feast, busWait, park, leavePlace,
}

/// The title for everything the cat does at home: the bar stays calm while
/// the cat gets on with its day.
const homeLabel = 'বাসায় · At home';

class ClipSpec {
  const ClipSpec(this.duration, this.label, {this.gag = false});

  /// Seconds; null for looping clips.
  final double? duration;
  final String label;

  /// A tap gag: may be cut short if the situation changes.
  final bool gag;
  bool get loops => duration == null;
}

const clipSpecs = <ClipId, ClipSpec>{
  ClipId.idle: ClipSpec(null, 'Looking around the goli'),
  ClipId.walk: ClipSpec(null, 'Trotting along'),
  ClipId.fast: ClipSpec(null, 'Zooming! Ears back'),
  ClipId.skid: ClipSpec(1.5, 'Skrrrt — slowing down'),
  ClipId.batPin: ClipSpec(1.6, 'Batting at its own pin', gag: true),
  ClipId.sitDown: ClipSpec(1.4, 'Sitting down for cha'),
  ClipId.tea: ClipSpec(null, 'Cha break'),
  ClipId.stashTea: ClipSpec(1.0, 'Oops — stashing the cha!'),
  ClipId.catchUp: ClipSpec(1.6, 'Hurrying to catch up'),
  ClipId.unfoldMap: ClipSpec(1.0, 'Unfolding the paper map'),
  ClipId.lost: ClipSpec(null, 'Hmm… where are we?'),
  ClipId.foldMap: ClipSpec(0.8, 'Found you! Folding the map'),
  ClipId.hopOnChair: ClipSpec(1.9, 'Clocking in…'),
  ClipId.typing: ClipSpec(null, 'কাজে আছি · At work'),
  ClipId.fishGag: ClipSpec(4.0, 'A fish?! On the screen?!', gag: true),
  ClipId.leaveOffice: ClipSpec(2.4, 'Glasses on the monitor — off we go'),
  ClipId.tuckIn: ClipSpec(2.3, homeLabel),
  ClipId.sleep: ClipSpec(null, homeLabel),
  ClipId.grumpy: ClipSpec(2.0, 'Five more minutes…', gag: true),
  ClipId.wakeUp: ClipSpec(2.4, 'Waking up — big stretch'),
  ClipId.sitAtDesk: ClipSpec(1.8, 'Glasses on, notebook open…'),
  ClipId.study: ClipSpec(null, 'পড়ছি · Doing homework'),
  ClipId.stuckGag: ClipSpec(2.8, 'Stuck on a sum…', gag: true),
  ClipId.closeBook: ClipSpec(1.6, 'Pencil down — off we go'),
  ClipId.headphonesOn: ClipSpec(1.7, 'Headphones on…'),
  ClipId.vibe: ClipSpec(null, 'আড্ডা · Hanging out'),
  ClipId.danceGag: ClipSpec(2.4, 'This is the good bit!', gag: true),
  ClipId.headphonesOff: ClipSpec(1.5, 'Headphones off — let\'s go'),
  ClipId.jamOn: ClipSpec(1.7, 'Traffic jam… headphones on'),
  ClipId.jam: ClipSpec(null, 'জ্যামে আটকে · Stuck in traffic'),
  ClipId.jamDance: ClipSpec(2.4, 'This is the good bit!', gag: true),
  ClipId.jamOff: ClipSpec(1.5, 'Moving again!'),
  ClipId.homeStroll: ClipSpec(1.6, homeLabel),
  ClipId.homeWake: ClipSpec(2.4, homeLabel),
  ClipId.tuckInHome: ClipSpec(2.3, homeLabel),
  ClipId.leaveHome: ClipSpec(1.3, 'Off we go'),
  ClipId.bath: ClipSpec(null, homeLabel),
  ClipId.eat: ClipSpec(null, homeLabel),
  ClipId.potty: ClipSpec(null, homeLabel),
  ClipId.lounge: ClipSpec(null, homeLabel),
  ClipId.gaming: ClipSpec(null, homeLabel),
  ClipId.bazar: ClipSpec(null, 'বাজারে · At the bazar'),
  ClipId.feast: ClipSpec(null, 'খাচ্ছি · Eating out'),
  ClipId.busWait: ClipSpec(null, 'বাসের অপেক্ষায় · Waiting for the bus'),
  ClipId.park: ClipSpec(null, 'পার্কে · At the park'),
  ClipId.leavePlace: ClipSpec(1.3, 'Off we go'),
};

// ---------------------------------------------------------------------------
// Base poses

Pose standPose() => Pose.zero().set({
      P.facing: 1, P.shadow: 1,
      P.bodyX: 0, P.bodyY: -27, P.bodyLen: 21, P.bodyH: 11.5,
      P.headX: 25, P.headY: -44,
      P.eyeOpen: 1,
      P.fnX: 13, P.fnY: -22, P.ffX: 9, P.ffY: -22,
      P.bnX: -13, P.bnY: -22, P.bfX: -17, P.bfY: -22,
      P.legLen: 0.92, P.legLenB: 0.92,
      P.tailX: -19, P.tailY: -31, P.tailEndX: -10, P.tailEndY: -22,
      P.tailBend: 6, P.tailCurl: 0.6,
      P.scarfNeck: 1, P.scarfFlow: 0.2,
      P.pinVis: 1,
    });

Pose sitPose() => Pose.zero().set({
      P.facing: 1, P.shadow: 0.9,
      P.bodyX: -1, P.bodyY: -21, P.bodyRot: -1.05, P.bodyLen: 15, P.bodyH: 12.5,
      P.haunch: 1,
      P.headX: 6, P.headY: -45,
      P.eyeOpen: 1,
      P.fnX: 6, P.fnY: -22, P.fnA1: 0.05, P.ffX: 2, P.ffY: -22, P.ffA1: 0.05,
      P.bnX: -6, P.bnY: -4, P.bnA1: 1.5, P.bfX: -9, P.bfY: -4, P.bfA1: 1.5,
      P.legLen: 0.92, P.legLenB: 0.45,
      P.tailX: -12, P.tailY: -6, P.tailEndX: 25, P.tailEndY: 5,
      P.tailBend: 7, P.tailCurl: 0.3,
      P.scarfNeck: 1, P.scarfFlow: 0.05,
      P.pinVis: 1,
    });

/// Seated on the office chair, paws reaching the keyboard.
Pose officePose() => sitPose().set({
      P.office: 1, P.pinVis: 0, P.shadow: 0,
      P.rootX: -4, P.rootY: -15,
      P.bodyRot: -0.95, P.headX: 9, P.headY: -45,
      P.fnY: -26, P.fnA1: 1.25, P.fnA2: 0.3,
      P.ffY: -26, P.ffA1: 1.2, P.ffA2: 0.35, P.ffX: 3,
      P.tailX: -13, P.tailY: -5, P.tailEndX: 9, P.tailEndY: 10,
      P.tailBend: -5, P.tailCurl: 1,
      P.scarfNeck: 0, P.glassesFace: 1,
      P.eyeOpen: 0.78, P.brow: -0.6, P.eyeLook: 0.7,
    });

/// Seated at a low study table, paws on the notebook, glasses on.
Pose studyPose() => sitPose().set({
      P.desk: 1, P.pinVis: 0, P.shadow: 0.85,
      P.rootX: -6,
      P.headX: 8, P.headY: -43, P.headRot: 0.3,
      // Forearms up on the table, paws on the notebook.
      P.fnX: 7, P.fnY: -22, P.fnA1: 0.81, P.fnA2: 1.06,
      P.ffX: 3, P.ffY: -22, P.ffA1: 0.77, P.ffA2: 1.16,
      P.glassesFace: 1, P.pencil: 1, P.lamp: 1,
      P.eyeOpen: 0.85, P.eyeLook: 0.9, P.brow: -0.3,
      P.scarfFlow: 0.05,
    });

/// Sitting with headphones on: on the hangout bench, or on the road in a jam.
Pose vibePose({bool road = false}) => sitPose().set({
      P.bench: road ? 0 : 1, P.pinVis: 0, P.shadow: road ? 0.9 : 0.55,
      P.rootY: road ? 0 : -11,
      P.headphones: 1, P.notes: 1, P.beat: 1,
      P.eyeOpen: 0.35, P.eyeLook: 0.2,
      P.tailX: -12, P.tailY: -6, P.tailEndX: 20, P.tailEndY: 2,
      P.scarfFlow: 0.1,
    });

Pose lyingPose() => Pose.zero().set({
      P.facing: 1, P.shadow: 0.7, P.home: 1, P.blanket: 1,
      P.bodyX: -4, P.bodyY: -11, P.bodyLen: 23, P.bodyH: 9.5, P.haunch: 0.6,
      P.headX: 22, P.headY: -13, P.headRot: 0.35,
      P.eyeOpen: 0, P.earFront: 0.25, P.earBack: 0.35,
      P.fnX: 12, P.fnY: -6, P.fnA1: 1.3, P.ffX: 8, P.ffY: -6, P.ffA1: 1.3,
      P.bnX: -18, P.bnY: -6, P.bnA1: 1.2, P.bfX: -22, P.bfY: -6, P.bfA1: 1.2,
      P.legLen: 0.35, P.legLenB: 0.35,
      P.tailX: -26, P.tailY: -9, P.tailEndX: -15, P.tailEndY: 3,
      P.tailBend: -4, P.tailCurl: 0.8,
      P.scarfNeck: 1, P.scarfFlow: 0,
    });

// ---------------------------------------------------------------------------
// Shared bits

/// Natural blinking: returns eye openness multiplier.
double blink(double time, [double every = 3.7]) {
  final u = time % every;
  return u < 0.12 ? (u < 0.06 ? 1 - u / 0.06 : (u - 0.06) / 0.06) : 1;
}

/// Damped spring wobble starting at [t0].
double wobble(double t, double t0, {double freq = 24, double decay = 6}) {
  if (t < t0) return 0;
  final d = t - t0;
  return math.exp(-decay * d) * math.sin(freq * d);
}

Pose _walkCycle(double t, ClipCtx c, {double hz = 2.1, double swing = 0.42}) {
  final a = c.amp;
  final ph = 2 * math.pi * t * hz * c.cadence;
  final p = standPose();
  final s = math.sin(ph), s2 = math.sin(ph + math.pi);
  final lift1 = math.max(0.0, math.cos(ph)), lift2 = math.max(0.0, -math.cos(ph));
  p.set({
    P.pinVis: 0,
    P.fnA1: swing * a * s, P.fnA2: -0.8 * a * lift1,
    P.bfA1: swing * a * s, P.bfA2: 0.7 * a * lift1,
    P.ffA1: swing * a * s2, P.ffA2: -0.8 * a * lift2,
    P.bnA1: swing * a * s2, P.bnA2: 0.7 * a * lift2,
    P.bodyY: -27 - 1.3 * a * math.sin(ph).abs(),
    P.headY: -44 - 1.6 * a * math.sin(ph - 0.5).abs(),
    P.headRot: 0.05 * a * math.sin(ph),
    P.tailEndY: -22 + 2 * math.sin(ph / 2),
    P.tailBend: 6 + 2 * math.sin(ph),
    P.scarfFlow: 0.4 + 0.2 * math.sin(ph).abs(),
    P.scarfPhase: c.time * 9,
    P.eyeOpen: blink(c.time),
    P.earFront: 0.08 * math.sin(ph),
  });
  return p;
}

Pose _fastCycle(double t, ClipCtx c) {
  // A rotary gallop: the spine gathers (all four paws under the body) and
  // stretches out (front paws reaching, hind legs pushing back), with a short
  // flight after each push. The head stays level, the way a real cat's does,
  // and the ears lie back in the wind instead of folding over.
  final a = c.amp;
  final ph = 2 * math.pi * t * 3.1 * c.cadence;
  final ext = math.cos(ph); // 1 stretched out, -1 gathered
  double leg(double off) => math.cos(ph + off);
  double fold(double off, {bool hind = false}) =>
      math.max(0.0, hind ? math.sin(ph + off) : -math.sin(ph + off));
  final p = standPose();
  p.set({
    P.pinVis: 0,
    P.bodyX: 2, P.bodyRot: 0.08 + 0.07 * a * math.sin(ph + 0.4),
    P.bodyLen: 23 + 3.2 * a * ext,
    P.bodyH: 11.2 - 0.5 * a * ext,
    P.bodyY: -27.5 - 1.2 * a * math.max(0, ext),
    // Head level: it moves far less than the body.
    P.headX: 31 + 1.8 * a * ext, P.headY: -40.5 - 0.5 * a * math.sin(ph), P.headRot: 0.1 - 0.04 * a * math.sin(ph + 0.4),
    P.earFront: 0.62 + 0.06 * math.sin(ph * 2 + 0.3), P.earBack: 0.68 + 0.06 * math.sin(ph * 2 + 1.1),
    P.earFlat: 0.35,
    P.eyeOpen: 0.82 * blink(c.time, 3.7), P.brow: -0.25, P.eyeLook: 0.4,
    P.mouth: 0.04,
    P.fnX: 15 + 1.5 * a * ext, P.ffX: 11 + 1.5 * a * ext, P.bnX: -12 - 1.5 * a * ext, P.bfX: -16 - 1.5 * a * ext,
    // Front pair reaches forward when stretched; the far paw leads a beat behind.
    P.fnA1: 0.95 * a * leg(0), P.fnA2: -1.1 * a * fold(0),
    P.ffA1: 0.95 * a * leg(0.45), P.ffA2: -1.1 * a * fold(0.45),
    // Hind pair pushes back when stretched, swings forward folded when gathered.
    P.bnA1: -0.85 * a * leg(0.25), P.bnA2: 0.95 * a * fold(0.25, hind: true),
    P.bfA1: -0.85 * a * leg(0.7), P.bfA2: 0.95 * a * fold(0.7, hind: true),
    // The tail streams out behind with a wave running down it.
    P.tailX: -21, P.tailY: -30, P.tailEndX: -23 - 1.5 * a * ext, P.tailEndY: -8 + 3 * math.sin(ph - 1.2),
    P.tailBend: 3 * math.sin(ph - 0.6), P.tailCurl: 0.15 + 0.1 * math.sin(ph - 1.8),
    P.scarfFlow: 1, P.scarfPhase: c.time * 16,
    // Flight just after the hind push; a soft landing on the front paws.
    P.speedLines: a, P.rootY: -3.2 * a * math.max(0, math.sin(ph + 1.1)), P.shadow: 0.85 + 0.1 * math.min(0, math.sin(ph + 1.1)),
    P.squash: 0.03 * a * math.max(0, -math.sin(ph + 1.1)),
  });
  return p;
}

/// Leg angles that put the near front paw at the mouth (sipping).
const _sip = (a1: 2.2, a2: 0.85);
const _hold = (a1: 1.9, a2: 1.84);

Pose _teaHold(ClipCtx c) => sitPose().set({
      P.cha: 1, P.steam: 1,
      P.fnA1: _hold.a1, P.fnA2: _hold.a2,
      P.eyeOpen: blink(c.time, 4.1),
      P.scarfPhase: c.time * 2,
    });

Pose _mapHold(ClipCtx c, double open) => sitPose().set({
      P.mapVis: 1, P.mapOpen: open,
      P.fnA1: 1.95, P.fnA2: 1.1,
      P.ffA1: 1.75, P.ffA2: 1.45,
      P.eyeOpen: 0.75, P.brow: 0.7,
      P.scarfPhase: c.time * 2,
    });

// ---------------------------------------------------------------------------
// Clips

Pose sampleClip(ClipId id, double t, ClipCtx c) {
  final a = c.amp;
  switch (id) {
    case ClipId.idle:
      final u = t % 8;
      final p = standPose();
      p.set({
        P.bodyH: 11.5 + 0.4 * math.sin(2 * math.pi * t / 2.6),
        P.headRot: keys(u, [[0, 0], [2, 0], [2.4, -0.12], [3.2, -0.12], [3.6, 0], [5, 0], [5.4, -0.18], [6.1, -0.18], [6.5, 0]]),
        P.eyeLook: keys(u, [[0, 0], [2, 0], [2.4, -1], [3.2, -1], [3.6, 0.3], [6.5, 0.3], [7, 0]]),
        P.earFront: keys(u, [[0, 0], [4.0, 0], [4.1, 0.6], [4.3, 0], [8, 0]]),
        P.tailEndX: -10 + 3 * math.sin(2 * math.pi * t / 4),
        P.tailCurl: 0.6 + 0.2 * math.sin(2 * math.pi * t / 3),
        P.eyeOpen: blink(c.time),
        P.scarfPhase: c.time * 2,
      });
      return p;

    case ClipId.walk:
      return _walkCycle(t, c);

    case ClipId.fast:
      return _fastCycle(t, c);

    case ClipId.skid:
      final p = _fastCycle(0.07, c);
      final brace = easeOut(span(t, 0, 0.25));
      final settle = easeInOut(span(t, 0.5, 0.8));
      final stand = standPose().set({P.pinVis: 0});
      p.blendFrom(stand, settle, P.values);
      p.set({
        P.rootX: -10 * a * (1 - easeOut(span(t, 0, 0.55))),
        P.speedLines: (1 - span(t, 0, 0.3)) * a,
        P.dust: (1 - span(t, 0.1, 0.9)) * a,
        P.scarfFlow: 1 - settle,
      });
      p.add({
        P.bodyRot: -0.2 * brace * (1 - settle),
        P.fnA1: 0.75 * brace * (1 - settle), P.ffA1: 0.6 * brace * (1 - settle),
        P.bnA1: 0.5 * brace * (1 - settle), P.bfA1: 0.4 * brace * (1 - settle),
      });
      final flop = keys(t, [[0, 0], [0.45, 0], [0.6, 1], [1.15, 1], [1.4, 0]]);
      p.set({
        P.scarfFace: flop,
        P.eyeWide: span(t, 0, 0.2) * (1 - span(t, 0.5, 0.6)),
        P.mouth: 0.6 * (1 - span(t, 0.4, 0.6)),
        P.headRot: 0.22 * a * wobble(t, 1.12, freq: 40, decay: 7),
        P.earFront: 0.6 * (1 - span(t, 1.1, 1.4)), P.earBack: 0.6 * (1 - span(t, 1.1, 1.4)),
        P.sweat: span(t, 0.7, 0.8) * (1 - span(t, 1.3, 1.5)),
        P.scarfPhase: c.time * 6,
      });
      return p;

    case ClipId.batPin:
      final p = standPose();
      final crouch = easeInOut(span(t, 0, 0.25)) * (1 - easeInOut(span(t, 1.2, 1.55)));
      final paw = keys(t, [[0, 0], [0.25, 2.4], [0.38, 2.4], [0.45, 0.6], [0.65, 0.6], [0.78, 2.2], [0.86, 2.2], [0.93, 0.55], [1.15, 0.5], [1.4, 0]]);
      final w = wobble(t, 0.45) + wobble(t, 0.93);
      p.set({
        P.rootX: -17 * crouch,
        P.bodyY: -27 + 3 * crouch, P.bodyRot: 0.12 * crouch,
        P.headY: -44 + 7 * crouch, P.headX: 25 + 2 * crouch,
        P.earFront: -0.3 * crouch, P.earBack: -0.3 * crouch,
        P.eyeWide: crouch, P.eyeLook: 0.6 * crouch,
        P.fnA1: paw, P.fnA2: paw > 1.5 ? -1.1 : 0,
        P.bnA1: -0.15 * crouch, P.bfA1: -0.15 * crouch,
        P.tailEndY: -24 - 4 * crouch, P.tailCurl: 0.6 + 0.5 * math.sin(t * 14) * crouch,
        P.pinWobble: w * a,
        P.eyeOpen: t > 1.25 ? 0.35 : 1,
        P.mouth: t > 1.25 ? 0.15 : 0,
        P.scarfPhase: c.time * 4,
      });
      return p;

    case ClipId.sitDown:
      return _sitDown(t, c);

    case ClipId.tea:
      return _teaBreak(t, c);

    case ClipId.stashTea:
      final p = _teaHold(c);
      final shove = easeInOut(span(t, 0.12, 0.45));
      final up = easeBack(span(t, 0.45, 0.85));
      p.set({
        P.exclaim: span(t, 0, 0.08) * (1 - span(t, 0.75, 1.0)),
        P.eyeWide: 1 - span(t, 0.8, 1.0),
        P.earFront: -0.25, P.earBack: -0.25,
        P.fnA1: _hold.a1 + (2.5 - _hold.a1) * shove,
        P.fnA2: _hold.a2 + (1.5 - _hold.a2) * shove,
        P.cha: 1 - span(t, 0.38, 0.5),
        P.steam: 1 - span(t, 0.1, 0.3),
        P.sweat: span(t, 0.15, 0.25),
        P.squash: 0.15 * a * (span(t, 0, 0.1) - span(t, 0.1, 0.2)),
      });
      final stand = standPose().set({P.pinVis: 0, P.sweat: 1, P.eyeWide: 1 - span(t, 0.8, 1.0)});
      final out = Pose.lerp(p, stand, up.clamp(0.0, 1.0));
      out[P.rootY] = -7 * a * math.sin(math.pi * span(t, 0.5, 0.95));
      out[P.exclaim] = p[P.exclaim];
      return out;

    case ClipId.catchUp:
      final p = _walkCycle(t, c, hz: 3.1, swing: 0.6);
      p.set({
        P.bodyRot: 0.06, P.headX: 28, P.headY: -42,
        P.earFront: 0.45, P.earBack: 0.5,
        P.scarfFlow: 0.9, P.sweat: 1 - span(t, 0.8, 1.6),
        P.speedLines: 0.4 * a * (1 - span(t, 1.0, 1.6)),
      });
      return p;

    case ClipId.unfoldMap:
      final p = Pose.lerp(standPose(), _mapHold(c, 0), easeInOut(span(t, 0, 0.4)));
      p.set({
        P.mapVis: span(t, 0.25, 0.4),
        P.mapOpen: easeBack(span(t, 0.45, 0.95)),
        P.question: span(t, 0.8, 1.0),
        P.pinVis: 0,
      });
      return p;

    case ClipId.lost:
      final u = t % 4.4;
      final p = _mapHold(c, 1);
      p.set({
        P.pinVis: 0,
        P.headRot: 0.2 * a * math.sin(2 * math.pi * t / 4.4),
        P.eyeLook: math.sin(2 * math.pi * t / 2.2),
        P.earFront: -0.2, P.earBack: 0.65,
        P.question: 1,
        P.mapRot: math.pi * keys(u, [[0, 0], [1.6, 0], [2.1, 1], [3.4, 1], [3.9, 0], [4.4, 0]]),
        P.eyeOpen: 0.7 * blink(c.time, 3.1),
      });
      return p;

    case ClipId.foldMap:
      final p = _mapHold(c, 1 - easeInOut(span(t, 0, 0.4)));
      p.set({P.mapVis: 1 - span(t, 0.35, 0.5), P.exclaim: span(t, 0, 0.1) * (1 - span(t, 0.5, 0.7)), P.pinVis: 0});
      return Pose.lerp(p, standPose().set({P.pinVis: 0}), easeInOut(span(t, 0.4, 0.8)))
        ..[P.mapVis] = p[P.mapVis]
        ..[P.exclaim] = p[P.exclaim];

    case ClipId.hopOnChair:
      final start = standPose().set({P.pinVis: 0, P.rootX: -28, P.glassesMon: 1});
      final seat = officePose().set({P.scarfNeck: 1, P.glassesFace: 0, P.glassesMon: 1, P.eyeOpen: 1, P.brow: 0});
      final jump = easeInOut(span(t, 0.55, 1.0));
      final p = Pose.lerp(start, seat, jump);
      p.set({
        P.office: easeOut(span(t, 0, 0.35)),
        P.rootY: seat[P.rootY] * jump - 14 * a * math.sin(math.pi * jump),
        P.squash: 0.22 * a * (span(t, 0.35, 0.5) - span(t, 0.5, 0.6)) + 0.18 * a * (span(t, 1.0, 1.08) - span(t, 1.08, 1.2)),
        P.scarfNeck: 1 - easeInOut(span(t, 1.15, 1.45)),
        P.glassesMon: 1 - span(t, 1.25, 1.35),
        P.glassesFace: span(t, 1.3, 1.4),
        P.scarfPhase: c.time * 3,
      });
      // Push the oversized glasses up the nose, then down to the keys.
      final push = keys(t, [[0, 0], [1.45, 0], [1.6, 1], [1.72, 1], [1.9, 0]]);
      if (t > 1.0) {
        p.blendFrom(officePose(), span(t, 1.0, 1.2), [P.fnA1, P.fnA2, P.ffA1, P.ffA2, P.eyeOpen, P.brow, P.eyeLook]);
        p[P.fnA1] += (2.5 - p[P.fnA1]) * push;
        p[P.fnA2] += (1.0 - p[P.fnA2]) * push;
      }
      return p;

    case ClipId.typing:
      return _typing(t, c);

    case ClipId.fishGag:
      final p = officePose();
      final lean = easeInOut(span(t, 0.3, 0.8)) * (1 - easeInOut(span(t, 2.6, 3.3)));
      final paw1 = keys(t, [[0, 0], [1.15, 0], [1.3, 1], [1.5, 1], [1.65, 0], [4, 0]]);
      final paw2 = keys(t, [[0, 0], [1.75, 0], [1.9, 1], [2.05, 1], [2.2, 0], [4, 0]]);
      final bonk = keys(t, [[0, 0], [2.15, 0], [2.3, 1], [2.45, 1], [2.7, 0], [4, 0]]);
      p.set({
        P.fish: span(t, 0, 0.3) * (1 - span(t, 2.7, 3.1)),
        P.fishX: keys(t, [[0, 0.5], [0.4, 0.5], [0.8, 0.3], [1.2, 0.55], [1.35, 0.88], [1.8, 0.8], [1.95, 0.15], [2.5, 0.4], [3, 0.5]]),
        P.fishY: 0.5 + 0.22 * math.sin(t * 5),
        P.monWobble: (wobble(t, 1.35) + wobble(t, 1.95) + 1.4 * wobble(t, 2.3)) * a,
        P.rootX: -4 + 5 * lean, P.bodyRot: -0.95 + 0.2 * lean,
        P.headX: 9 + 6 * lean + 6 * bonk, P.headY: -45 + 2 * lean,
        P.earFront: -0.4 * lean, P.earBack: -0.4 * lean,
        P.eyeWide: lean, P.eyeOpen: 1, P.brow: -0.6 + 0.6 * lean,
        P.fnA1: 1.25 + (2.05 - 1.25) * paw1, P.fnA2: 0.3 - 0.5 * paw1,
        P.ffA1: 1.2 + (2.1 - 1.2) * paw2, P.ffA2: 0.35 - 0.5 * paw2,
        P.squash: 0.12 * bonk * a,
        P.tailCurl: 1 + 0.5 * math.sin(t * 12) * lean,
      });
      final push = keys(t, [[0, 0], [3.2, 0], [3.4, 1], [3.6, 1], [3.85, 0]]);
      p[P.fnA1] += (2.5 - p[P.fnA1]) * push;
      p[P.fnA2] += (1.0 - p[P.fnA2]) * push;
      if (t > 3.1) p[P.eyeLook] = 0.7;
      return p;

    case ClipId.leaveOffice:
      final p = officePose();
      final reach = keys(t, [[0, 0], [0.15, 1], [0.35, 1], [0.6, 0]]);
      p.set({
        P.fnA1: 1.25 + (2.5 - 1.25) * reach,
        P.fnA2: 0.3 + 0.7 * reach,
        P.glassesFace: 1 - span(t, 0.3, 0.4),
        P.glassesMon: span(t, 0.5, 0.6),
        P.headRot: -0.25 * keys(t, [[0, 0], [0.6, 0], [0.8, 1], [1.05, 1], [1.2, 0]]),
        P.scarfNeck: span(t, 0.85, 1.05),
        P.brow: 0, P.eyeOpen: 1, P.eyeLook: keys(t, [[0, 0.7], [0.6, 0.7], [0.8, -1], [1.1, -1], [1.3, 0]]),
      });
      p[P.ffA1] += (2.4 - p[P.ffA1]) * keys(t, [[0, 0], [0.6, 0], [0.8, 1], [1.0, 1], [1.15, 0]]);
      final hop = easeInOut(span(t, 1.2, 1.6));
      final walk = _walkCycle(t, c).set({P.glassesMon: 1, P.office: 1});
      final out = Pose.lerp(p, walk, hop);
      out[P.rootY] = p[P.rootY] * (1 - hop) - 9 * a * math.sin(math.pi * hop);
      out[P.office] = 1 - easeInOut(span(t, 1.7, 2.4));
      out[P.glassesMon] = p[P.glassesMon];
      out[P.scarfNeck] = p[P.scarfNeck];
      return out;

    // ---- education: homework at a low desk ------------------------------
    case ClipId.sitAtDesk:
      final start = standPose().set({P.pinVis: 0, P.rootX: -24});
      final seat = studyPose().set({P.glassesFace: 0, P.pencil: 0, P.eyeOpen: 1, P.brow: 0, P.eyeLook: 0, P.headRot: 0});
      final sit = easeInOut(span(t, 0.2, 0.8));
      final p = Pose.lerp(start, seat, sit);
      // Glasses pushed up the nose, then the pencil is picked up and the head drops to the page.
      final push = keys(t, [[0, 0], [0.85, 0], [1.0, 1], [1.12, 1], [1.3, 0]]);
      p.set({
        P.desk: easeOut(span(t, 0, 0.4)),
        P.lamp: span(t, 0.3, 0.5),
        P.glassesFace: span(t, 0.95, 1.05),
        P.pencil: span(t, 1.3, 1.45),
        P.headRot: 0.3 * easeInOut(span(t, 1.4, 1.75)),
        P.eyeLook: 0.9 * easeInOut(span(t, 1.4, 1.75)),
        P.eyeOpen: 1 - 0.15 * span(t, 1.4, 1.75),
        P.squash: 0.15 * a * (span(t, 0.75, 0.85) - span(t, 0.85, 0.95)),
        P.scarfPhase: c.time * 3,
      });
      p[P.fnA1] += (2.5 - p[P.fnA1]) * push;
      p[P.fnA2] += (1.0 - p[P.fnA2]) * push;
      return p;

    case ClipId.study:
      return _studying(t, c);

    case ClipId.stuckGag:
      final p = studyPose();
      final scratch = keys(t, [[0, 0], [0.25, 1], [1.6, 1], [1.9, 0]]);
      final idea = span(t, 1.9, 2.05) * (1 - span(t, 2.6, 2.8));
      p.set({
        P.headRot: 0.3 - 0.45 * scratch, P.eyeLook: 0.9 - 1.4 * scratch, P.brow: -0.3 + 1.1 * scratch,
        P.eyeOpen: 0.85 + 0.15 * scratch,
        P.question: scratch,
        // Far paw scratches behind the ear; near paw taps the pencil.
        P.ffA1: 0.77 + (2.35 - 0.77) * scratch, P.ffA2: 1.16 - 0.3 * scratch,
        P.fnA2: 1.06 + 0.12 * math.sin(t * 22) * scratch,
        P.earBack: 0.3 * math.max(0, math.sin(t * 9)) * scratch,
        P.exclaim: idea,
        P.mouth: 0.3 * idea,
        P.write: ((t / 9) % 1) + 0.3 * span(t, 2.0, 2.8),
        P.scarfPhase: c.time * 2,
      });
      if (t > 2.0) p[P.fnA2] = 1.06 + 0.2 * math.sin(t * 40) * a;
      return p;

    case ClipId.closeBook:
      final p = studyPose();
      final reach = keys(t, [[0, 0], [0.15, 1], [0.35, 1], [0.55, 0]]);
      p.set({
        P.pencil: 1 - span(t, 0.1, 0.2),
        P.fnA1: 0.81 + (2.5 - 0.81) * reach, P.fnA2: 1.06 - 0.1 * reach,
        P.glassesFace: 1 - span(t, 0.3, 0.4),
        P.headRot: 0.3 * (1 - span(t, 0.1, 0.4)), P.eyeLook: 0.9 * (1 - span(t, 0.1, 0.4)),
        P.eyeOpen: 1, P.brow: 0,
        P.lamp: 1 - span(t, 0.5, 0.6),
      });
      final up = easeInOut(span(t, 0.6, 1.1));
      final walk = _walkCycle(t, c).set({P.desk: 1});
      final out = Pose.lerp(p, walk, up);
      out[P.rootY] = -6 * a * math.sin(math.pi * up);
      out[P.desk] = 1 - easeInOut(span(t, 1.1, 1.6));
      out[P.glassesFace] = p[P.glassesFace];
      out[P.pencil] = p[P.pencil];
      out[P.lamp] = p[P.lamp];
      return out;

    // ---- hangout: headphones on a bench ----------------------------------
    case ClipId.headphonesOn:
      final start = standPose().set({P.pinVis: 0, P.rootX: -4});
      final seat = vibePose().set({P.headphones: 0, P.notes: 0, P.beat: 0, P.eyeOpen: 1, P.eyeLook: 0});
      final hop = easeInOut(span(t, 0.2, 0.7));
      final p = Pose.lerp(start, seat, hop);
      final reach = keys(t, [[0, 0], [0.8, 0], [1.0, 1], [1.15, 1], [1.35, 0]]);
      p.set({
        P.bench: easeOut(span(t, 0, 0.3)),
        P.rootY: -11 * hop - 8 * a * math.sin(math.pi * hop),
        P.squash: 0.18 * a * (span(t, 0.7, 0.78) - span(t, 0.78, 0.9)),
        P.headphones: span(t, 1.08, 1.15),
        P.notes: span(t, 1.35, 1.7), P.beat: span(t, 1.3, 1.5),
        P.eyeOpen: 1 - 0.65 * span(t, 1.4, 1.7),
        P.mouth: 0.25 * span(t, 1.15, 1.3) * (1 - span(t, 1.5, 1.7)),
        P.scarfPhase: c.time * 3,
      });
      p[P.fnA1] += (2.45 - p[P.fnA1]) * reach;
      p[P.fnA2] += (0.9 - p[P.fnA2]) * reach;
      return p;

    case ClipId.vibe:
      return _vibing(t, c);

    case ClipId.danceGag:
      return _dance(t, c, road: false);

    // ---- traffic jam: same headphones, no bench, sitting on the road -------
    case ClipId.jamOn:
      final start = standPose().set({P.pinVis: 0});
      final seat = vibePose(road: true).set({P.headphones: 0, P.notes: 0, P.beat: 0, P.eyeOpen: 1, P.eyeLook: 0});
      final sit = easeInOut(span(t, 0.1, 0.6));
      final p = Pose.lerp(start, seat, sit);
      final reach = keys(t, [[0, 0], [0.75, 0], [0.95, 1], [1.1, 1], [1.3, 0]]);
      // A look up the road and a sigh before giving in to the music.
      p.set({
        P.headRot: -0.22 * keys(t, [[0, 0], [0.1, 0], [0.3, 1], [0.65, 1], [0.85, 0]]),
        P.eyeLook: keys(t, [[0, 0], [0.3, 1], [0.65, 1], [0.85, 0]]),
        P.brow: 0.5 * keys(t, [[0, 0], [0.3, 1], [0.9, 1], [1.1, 0]]),
        P.mouth: 0.25 * keys(t, [[0, 0], [0.6, 0], [0.7, 1], [0.85, 0]]),
        P.headphones: span(t, 1.03, 1.1),
        P.notes: span(t, 1.3, 1.7), P.beat: span(t, 1.3, 1.5),
        P.eyeOpen: 1 - 0.65 * span(t, 1.35, 1.7),
        P.scarfPhase: c.time * 3,
      });
      p[P.fnA1] += (2.45 - p[P.fnA1]) * reach;
      p[P.fnA2] += (0.9 - p[P.fnA2]) * reach;
      return p;

    case ClipId.jam:
      final p = _vibing(t, c, road: true);
      // Every so often: a glance up the road. Still not moving. Back to the song.
      final u = t % 14;
      final look = keys(u, [[0, 0], [9.0, 0], [9.4, 1], [10.6, 1], [11.0, 0]]);
      p.set({
        P.headRot: p[P.headRot] * (1 - look) - 0.2 * look,
        P.eyeOpen: math.max(p[P.eyeOpen], look),
        P.eyeLook: p[P.eyeLook] * (1 - look) + 1.0 * look,
        P.brow: 0.5 * look,
        P.earFront: p[P.earFront] + 0.4 * look,
        P.mouth: u > 10.6 && u < 11.0 ? 0.2 : p[P.mouth],
      });
      return p;

    case ClipId.jamDance:
      return _dance(t, c, road: true);

    case ClipId.jamOff:
      final p = vibePose(road: true);
      final reach = keys(t, [[0, 0], [0.1, 1], [0.3, 1], [0.5, 0]]);
      p.set({
        P.notes: 1 - span(t, 0, 0.2), P.beat: 1 - span(t, 0, 0.3),
        P.headphones: 1 - span(t, 0.28, 0.36),
        P.eyeOpen: 0.35 + 0.65 * span(t, 0.2, 0.4),
        P.exclaim: span(t, 0.05, 0.15) * (1 - span(t, 0.6, 0.8)),
      });
      p[P.fnA1] += (2.45 - p[P.fnA1]) * reach;
      p[P.fnA2] += (0.9 - p[P.fnA2]) * reach;
      final up = easeInOut(span(t, 0.55, 1.0));
      final out = Pose.lerp(p, standPose().set({P.pinVis: 0}), up);
      out[P.rootY] = -5 * a * math.sin(math.pi * up);
      out[P.headphones] = p[P.headphones];
      out[P.notes] = p[P.notes];
      out[P.exclaim] = p[P.exclaim];
      return out;

    case ClipId.headphonesOff:
      final p = vibePose();
      final reach = keys(t, [[0, 0], [0.1, 1], [0.3, 1], [0.5, 0]]);
      p.set({
        P.notes: 1 - span(t, 0, 0.2), P.beat: 1 - span(t, 0, 0.3),
        P.headphones: 1 - span(t, 0.28, 0.36),
        P.eyeOpen: 0.35 + 0.65 * span(t, 0.2, 0.4),
      });
      p[P.fnA1] += (2.45 - p[P.fnA1]) * reach;
      p[P.fnA2] += (0.9 - p[P.fnA2]) * reach;
      final hop = easeInOut(span(t, 0.55, 1.0));
      final walk = _walkCycle(t, c).set({P.bench: 1});
      final out = Pose.lerp(p, walk, hop);
      out[P.rootY] = -11 * (1 - hop) - 7 * a * math.sin(math.pi * hop);
      out[P.bench] = 1 - easeInOut(span(t, 1.0, 1.5));
      out[P.headphones] = p[P.headphones];
      out[P.notes] = p[P.notes];
      return out;

    case ClipId.tuckIn:
      final yawn = keys(t, [[0, 0], [0.3, 0], [0.55, 1], [0.95, 1], [1.15, 0]]);
      final st = standPose().set({P.pinVis: 0, P.home: easeOut(span(t, 0, 0.4)), P.blanket: 0});
      st.set({P.mouth: yawn, P.eyeOpen: 1 - yawn, P.headRot: -0.25 * yawn, P.earBack: 0.3 * yawn, P.earFront: 0.3 * yawn});
      final lie = lyingPose().set({P.blanket: 0});
      final p = Pose.lerp(st, lie, easeInOut(span(t, 1.05, 1.55)));
      p.set({
        P.home: easeOut(span(t, 0, 0.4)),
        P.blanket: easeOut(span(t, 1.5, 2.2)),
        P.zzz: span(t, 2.0, 2.3),
        P.time: c.time,
      });
      return p;

    case ClipId.sleep:
      return _sleeping(t, c);

    // ---- home life ------------------------------------------------------------
    case ClipId.homeStroll:
      return _homeStroll(t, c);
    case ClipId.homeWake:
      return sampleClip(ClipId.wakeUp, t, c)..[P.home] = 1;
    case ClipId.tuckInHome:
      return sampleClip(ClipId.tuckIn, t, c)..[P.home] = 1;
    case ClipId.leaveHome:
      final st = standPose().set({P.pinVis: 0, P.home: 1, P.eyeOpen: blink(c.time)});
      final out = Pose.lerp(st, _walkCycle(t, c), easeInOut(span(t, 0.45, 1.1)));
      out[P.home] = 1 - easeInOut(span(t, 0.35, 1.2));
      out[P.rootY] = -5 * a * math.sin(math.pi * span(t, 0.2, 0.6));
      return out;
    case ClipId.bath:
      return _bath(t, c);
    case ClipId.eat:
      return _eat(t, c);
    case ClipId.potty:
      return _potty(t, c);
    case ClipId.lounge:
      return _lounge(t, c);
    case ClipId.gaming:
      return _gaming(t, c);
    case ClipId.bazar:
      return _bazar(t, c);
    case ClipId.feast:
      return _feast(t, c);
    case ClipId.busWait:
      return _busWait(t, c);
    case ClipId.park:
      return _park(t, c);
    case ClipId.leavePlace:
      final st = standPose().set({P.pinVis: 0, P.eyeOpen: blink(c.time)});
      return Pose.lerp(st, _walkCycle(t, c), easeInOut(span(t, 0.35, 1.1)));

    case ClipId.grumpy:
      final p = _sleeping(0, c);
      p.set({
        P.bubble: 0, P.zzz: span(t, 1.6, 2.0), P.dream: 0,
        P.impact: 0.5 * (1 - span(t, 0, 0.2)),
        P.eyeOpen: keys(t, [[0, 0], [0.25, 0], [0.4, 0.45], [0.9, 0.45], [1.0, 0]]),
        P.brow: -1,
        P.blanketHead: keys(t, [[0, 0], [0.9, 0], [1.2, 1], [1.7, 1], [2.0, 0]]),
      });
      return p;

    case ClipId.wakeUp:
      final p = _sleeping(0, c);
      p.set({
        P.bubble: 0, P.zzz: 0, P.dream: 0,
        P.impact: 0.45 * (1 - span(t, 0, 0.2)),
        P.eyeOpen: span(t, 0.2, 0.35), P.exclaim: span(t, 0.2, 0.3) * (1 - span(t, 0.6, 0.8)),
        P.blanket: 1 - easeIn(span(t, 0.5, 1.0)),
      });
      final stretch = standPose().set({
        P.pinVis: 0, P.home: 1,
        P.bodyRot: 0.32, P.bodyY: -21, P.bodyX: 1,
        P.headX: 27, P.headY: -28, P.headRot: -0.2,
        P.fnA1: 1.25, P.ffA1: 1.15, P.fnA2: 0.1, P.ffA2: 0.1, P.fnY: -14, P.ffY: -14,
        P.mouth: 1, P.eyeOpen: 0, P.earBack: 0.4, P.earFront: 0.4,
        P.tailEndY: -26, P.tailEndX: -4,
      });
      final s1 = easeInOut(span(t, 0.9, 1.4));
      final s2 = easeInOut(span(t, 1.8, 2.3));
      final out = Pose.lerp(Pose.lerp(p, stretch, s1), standPose().set({P.pinVis: 0, P.home: 1}), s2);
      out[P.home] = 1 - span(t, 1.8, 2.4);
      out[P.blanket] = p[P.blanket];
      out[P.exclaim] = p[P.exclaim];
      out[P.impact] = p[P.impact];
      return out;
  }
}

Pose _typing(double t, ClipCtx c) {
  final a = c.amp;
  const loop = 7.0;
  final cycle = (t / loop).floor();
  final u = t % loop;
  // Every so often (two cycles in three) the Enter gag plays.
  final gag = hashNoise(cycle, 7) > -0.33 && cycle > 0 || cycle == 0;
  final p = officePose();
  final ph = 2 * math.pi * u * 2.6;
  final typingPart = !gag || u < 4.2 || u > 6.75;
  if (typingPart) {
    final l = math.max(0.0, math.sin(ph)), r = math.max(0.0, math.sin(ph + math.pi));
    p.set({
      P.fnA1: 1.25 + 0.4 * l * a, P.fnA2: 0.3 + 0.2 * l,
      P.ffA1: 1.2 + 0.4 * r * a, P.ffA2: 0.35 + 0.2 * r,
      P.keyFlash: math.max(0.0, -math.sin(ph * 2)),
      P.headY: -45 + 0.8 * a * math.sin(2 * math.pi * u * 1.3),
      P.headRot: 0.03 * a * math.sin(2 * math.pi * u * 0.65),
    });
  }
  if (gag && u >= 4.2 && u <= 6.75) {
    final raise = easeOut(span(u, 4.2, 4.65));
    final slam = span(u, 4.68, 4.74);
    p.set({
      P.fnA1: 1.25 + (2.95 - 1.25) * raise - (2.95 - 1.32) * slam,
      P.fnA2: 0.3 - 0.2 * raise + 0.15 * slam,
      P.headRot: -0.08 * raise * (1 - slam),
      P.impact: slam * (1 - span(u, 4.9, 5.3)),
      P.enterFlash: slam * (1 - span(u, 4.8, 5.4)),
      P.keyFlash: slam * (1 - span(u, 4.85, 5.1)),
      P.squash: 0.12 * a * slam * (1 - span(u, 4.74, 4.9)),
      P.eyeOpen: u > 5.3 && u < 5.42 ? 0.1 : 0.72,
      P.brow: -0.8,
    });
    // Chair rolls back a few inches, then the cat scoots back in three shuffles.
    final rollBack = easeOut(span(u, 4.74, 5.25));
    final step1 = easeInOut(span(u, 5.6, 5.8)), step2 = easeInOut(span(u, 5.95, 6.15)), step3 = easeInOut(span(u, 6.3, 6.5));
    final chair = -10 * rollBack + (10 / 3) * (step1 + step2 + step3);
    p[P.chairX] = chair * a.clamp(0.5, 1.0);
    p[P.rootX] = -4 + p[P.chairX];
    final hop = math.sin(math.pi * step1) + math.sin(math.pi * step2) + math.sin(math.pi * step3);
    p[P.rootY] = -15 - 1.6 * a * hop;
    if (u > 5.25) {
      p[P.fnA1] = 1.32;
      p[P.fnA2] = 0.45;
    }
  }
  p[P.screenText] = ((t / 9) % 1);
  p[P.time] = c.time;
  p[P.tailCurl] = 1 + 0.15 * math.sin(t * 2);
  return p;
}

/// Writing: the pencil paw scribbles, the head follows the line, and now
/// and then the cat sits back to read what it wrote.
Pose _studying(double t, ClipCtx c) {
  final a = c.amp;
  const loop = 11.0;
  final u = t % loop;
  final p = studyPose();
  final reading = keys(u, [[0, 0], [7.4, 0], [7.9, 1], [9.6, 1], [10.1, 0]]);
  final ph = 2 * math.pi * u * 2.8;
  p.set({
    P.fnA1: 0.81 + 0.07 * a * math.sin(ph) * (1 - reading),
    P.fnA2: 1.06 + 0.14 * a * math.sin(ph * 1.5) * (1 - reading),
    P.headRot: 0.3 - 0.35 * reading + 0.03 * a * math.sin(ph / 2),
    P.headX: 8 + 1.5 * a * math.sin(ph / 4) * (1 - reading),
    P.eyeLook: 0.9 - 0.6 * reading + 0.1 * math.sin(ph / 3),
    P.eyeOpen: (u > 8.3 && u < 8.45 ? 0.1 : 0.85) * blink(c.time, 5.3),
    P.brow: -0.3 + 0.2 * reading,
    P.mouth: u > 8.5 && u < 9.2 ? 0.2 : 0,
    P.write: (t / loop) % 1,
    P.tailCurl: 0.3 + 0.25 * math.sin(t * 1.7),
    P.earFront: 0.1 * math.max(0, math.sin(t * 3.1)),
    P.scarfPhase: c.time * 2,
  });
  return p;
}

/// The tap gag: bounce, paws in the air, extra notes.
Pose _dance(double t, ClipCtx c, {required bool road}) {
  final a = c.amp;
  final p = _vibing(t, c, road: road);
  final on = span(t, 0, 0.2) * (1 - span(t, 2.0, 2.4));
  final beat = (math.sin(2 * math.pi * t * 2.2)).abs();
  p.set({
    P.rootY: (road ? 0 : -11) - 5 * a * beat * on,
    P.squash: 0.12 * a * (1 - beat) * on,
    P.headRot: 0.22 * a * math.sin(2 * math.pi * t * 2.2) * on,
    P.eyeOpen: 0.05, P.mouth: 0.4 * on,
    P.earFront: 0.4 * beat * on, P.earBack: 0.4 * beat * on,
    P.fnA1: 0.05 + 2.2 * on * (0.5 + 0.5 * math.sin(2 * math.pi * t * 2.2)),
    P.ffA1: 0.05 + 2.2 * on * (0.5 + 0.5 * math.sin(2 * math.pi * t * 2.2 + math.pi)),
    P.notes: 1 + on, P.exclaim: span(t, 0, 0.1) * (1 - span(t, 0.5, 0.7)),
  });
  return p;
}

/// Head bobbing to the beat, paw tapping, tail swaying; notes drift up.
Pose _vibing(double t, ClipCtx c, {bool road = false}) {
  final a = c.amp;
  final bpm = 2.0; // beats per second
  final ph = 2 * math.pi * t * bpm;
  final beat = math.max(0.0, math.sin(ph));
  final p = vibePose(road: road);
  p.set({
    P.headY: -45 - 1.6 * a * beat,
    P.headRot: 0.1 * a * math.sin(ph / 2),
    P.bodyH: 12.5 + 0.3 * a * beat,
    P.fnA1: 0.05 + 0.35 * a * math.max(0, math.sin(ph + math.pi / 2)), P.fnA2: -0.3 * a * beat,
    P.tailEndY: 2 - 4 * math.sin(ph / 4), P.tailBend: 7 + 3 * math.sin(ph / 2),
    P.tailCurl: 0.3 + 0.3 * math.sin(ph / 2),
    P.earFront: 0.12 * a * beat, P.earBack: 0.08 * a * beat,
    P.eyeOpen: 0.35 * blink(c.time, 6.0),
    P.mouth: (t % 9) > 6 && (t % 9) < 7.2 ? 0.2 * a : 0, // humming along
    P.beat: beat,
    P.time: c.time,
  });
  return p;
}

Pose _sleeping(double t, ClipCtx c) {
  final a = c.amp;
  final p = lyingPose();
  final cycle = (t / 6).floor();
  final u = t % 6;
  final breath = math.sin(2 * math.pi * t / 3);
  final dreamCycle = cycle % 3 == 1;
  p.set({
    P.bodyH: 9.5 + 0.7 * a * breath,
    P.headY: -13 + 0.3 * a * breath,
    P.bubble: dreamCycle ? 0 : clamp01(0.45 + 0.45 * breath),
    P.zzz: 1, P.time: c.time,
    P.earFront: 0.25 + keys(u, [[0, 0], [4.0, 0], [4.08, -0.5], [4.2, 0], [4.28, -0.4], [4.4, 0], [6, 0]]),
    P.kick: cycle.isOdd ? keys(u, [[0, 0], [2.0, 0], [2.12, 1], [2.25, 0.2], [2.37, 1], [2.55, 0], [6, 0]]) * a : 0,
    P.tailCurl: 0.8 + (u > 3 && u < 4 ? 0.35 * math.sin(u * 18) : 0),
    P.dream: dreamCycle ? keys(u, [[0, 0], [0.5, 1], [5.2, 1], [5.8, 0]]) : 0,
    P.dreamKind: (cycle ~/ 3).isEven ? 0 : 1,
    P.mouth: dreamCycle && u > 2 && u < 3 ? 0.2 * (0.5 + 0.5 * math.sin(u * 20)) : 0,
  });
  return p;
}

// ---------------------------------------------------------------------------
// Home life

/// Sitting on the mat at home.
Pose _homeSit(ClipCtx c) => sitPose().set({
      P.home: 1, P.pinVis: 0, P.shadow: 0.8,
      P.eyeOpen: blink(c.time, 4.3),
      P.scarfPhase: c.time * 2,
    });

/// Sit down from standing over the first [dur] seconds.
Pose _settle(Pose seated, double t, {double dur = 0.7}) {
  if (t >= dur) return seated;
  final st = standPose().set({P.pinVis: 0, P.home: 1});
  return Pose.lerp(st, seated, easeInOut(t / dur));
}

/// Between two home activities: stand, look around, a little hop.
Pose _homeStroll(double t, ClipCtx c) {
  final a = c.amp;
  final p = standPose().set({P.pinVis: 0, P.home: 1});
  p.set({
    P.headRot: -0.15 * keys(t, [[0, 0], [0.3, 1], [0.7, 1], [0.9, -0.6], [1.3, -0.6], [1.6, 0]]),
    P.eyeLook: keys(t, [[0, 0], [0.3, -1], [0.7, -1], [0.9, 0.8], [1.3, 0.8], [1.6, 0]]),
    P.tailCurl: 0.6 + 0.4 * math.sin(t * 7),
    P.rootY: -4 * a * math.sin(math.pi * span(t, 0.95, 1.3)),
    P.earFront: 0.3 * span(t, 0.9, 1.0) * (1 - span(t, 1.2, 1.4)),
    P.eyeOpen: blink(c.time),
    P.scarfPhase: c.time * 3,
  });
  return p;
}

/// Bucket and mug bath: scoop, splash over the head, shiver, soap up.
Pose _bath(double t, ClipCtx c) {
  final a = c.amp;
  final p = _homeSit(c).set({
    P.bucket: easeOut(span(t, 0, 0.5)),
    P.mug: span(t, 0.5, 0.8),
    P.fnA1: _hold.a1, P.fnA2: _hold.a2,
  });
  if (t < 1.0) {
    return _settle(p, t)
      ..[P.bucket] = p[P.bucket]
      ..[P.mug] = p[P.mug];
  }
  final u = (t - 1.0) % 6.0;
  final scoop = keys(u, [[0, 0], [0.4, 1], [0.8, 1], [1.0, 0]]);
  final raise = keys(u, [[0, 0], [0.9, 0], [1.3, 1], [1.7, 1], [2.1, 0]]);
  final shiver = u > 2.5 && u < 3.4;
  p.set({
    P.fnA1: _hold.a1 + (0.9 - _hold.a1) * scoop + (2.9 - _hold.a1) * raise,
    P.fnA2: _hold.a2 + (0.3 - _hold.a2) * scoop + (0.3 - _hold.a2) * raise,
    P.splash: u >= 1.4 && u < 2.4 ? span(u, 1.4, 2.4) : (u >= 2.5 && u < 3.4 ? 1 + span(u, 2.5, 3.4) : 0),
    P.eyeOpen: u > 1.35 && u < 5.6 ? 0.0 : blink(c.time, 4.3),
    P.earFront: -0.4 * span(u, 1.4, 1.6) * (1 - span(u, 3.3, 3.6)),
    P.earBack: -0.4 * span(u, 1.4, 1.6) * (1 - span(u, 3.3, 3.6)),
    P.mouth: u > 1.5 && u < 2.2 ? 0.45 : (u > 3.8 && u < 5.4 ? 0.15 : 0),
    P.headRot: shiver ? 0.22 * a * math.sin(u * 46) : -0.1 * raise,
    P.squash: shiver ? 0.04 * a * math.sin(u * 46) : 0,
  });
  // Far paw lathers the head; the foam stays until the next splash rinses it.
  final lather = keys(u, [[0, 0], [3.6, 0], [3.9, 1], [5.3, 1], [5.6, 0]]);
  p[P.ffA1] += (2.4 - p[P.ffA1]) * lather;
  p[P.ffA2] += (0.9 + 0.25 * math.sin(u * 18) - p[P.ffA2]) * lather;
  p[P.foam] = u >= 3.7 ? span(u, 3.7, 4.6) : (u < 1.6 && t > 7 ? 1 - span(u, 1.35, 1.6) : 0);
  return p;
}

/// Rice and a fish: lean in, nibble, chew with eyes shut. The fish gets smaller.
Pose _eat(double t, ClipCtx c) {
  final a = c.amp;
  final p = _homeSit(c).set({P.plate: easeOut(span(t, 0, 0.5)), P.bite: 0});
  if (t < 1.0) return _settle(p, t)..[P.plate] = p[P.plate];
  final cycle = ((t - 1) / 4).floor();
  final u = (t - 1) % 4;
  final lean = keys(u, [[0, 0], [0.5, 1], [1.2, 1], [1.6, 0]]);
  final nib = u > 0.5 && u < 1.2 ? math.max(0.0, math.sin((u - 0.5) * 18)) : 0.0;
  final chew = u > 1.5 && u < 3.6 ? 0.5 + 0.5 * math.sin(u * 16) : 0.0;
  p.set({
    P.bite: clamp01((t - 1) / 55),
    P.bodyRot: -1.05 + 0.4 * lean, P.bodyX: -1 + 2 * lean,
    P.headX: 6 + 9 * lean, P.headY: -45 + 21 * lean + 1.5 * nib * a, P.headRot: 0.55 * lean,
    P.eyeOpen: lean > 0.5 ? 0.6 : (chew > 0 ? 0.05 : blink(c.time, 4.3)),
    P.mouth: 0.3 * nib + 0.22 * chew,
    P.earFront: 0.1 * chew, P.earBack: 0.1 * chew,
    P.tailCurl: 0.3 + 0.35 * math.max(0, math.sin(t * 2.4)),
  });
  // Now and then a satisfied burp.
  if (cycle % 4 == 3) {
    final burp = keys(u, [[0, 0], [2.4, 0], [2.55, 1], [3.4, 1], [3.6, 0]]);
    p[P.say] = burp;
    p[P.sayKind] = 1;
    p[P.squash] = 0.08 * a * span(u, 2.4, 2.5) * (1 - span(u, 2.5, 2.7));
    if (burp > 0.5) p[P.mouth] = 0.5;
  }
  return p;
}

/// The litter tray with the newspaper: read, strain, plop, relief.
Pose _potty(double t, ClipCtx c) {
  final a = c.amp;
  final p = sitPose().set({
    P.home: 1, P.pinVis: 0, P.shadow: 0.6, P.litter: easeOut(span(t, 0, 0.4)),
    P.rootY: -2,
    P.fnA1: 1.95, P.fnA2: 1.1, P.ffA1: 1.75, P.ffA2: 1.45,
    P.paper: span(t, 0.9, 1.2), P.eyeOpen: 0.85, P.eyeLook: 0.5,
    P.scarfPhase: c.time * 2,
  });
  if (t < 1.2) {
    final st = standPose().set({P.pinVis: 0, P.home: 1});
    final hop = easeInOut(span(t, 0.2, 0.8));
    final out = Pose.lerp(st, p, hop);
    out[P.rootY] = -2 * hop - 9 * a * math.sin(math.pi * hop);
    out[P.litter] = p[P.litter];
    out[P.paper] = p[P.paper];
    return out;
  }
  final u = (t - 1.2) % 12;
  final strain = keys(u, [[0, 0], [4.0, 0], [4.3, 1], [6.3, 1], [6.5, 0]]);
  final relief = keys(u, [[0, 0], [6.6, 0], [6.8, 1], [8.6, 1], [9.0, 0]]);
  p.set({
    P.eyeLook: 0.5 + 0.45 * math.sin(u * 1.6) * (1 - strain) * (1 - relief),
    P.eyeOpen: 0.85 * (1 - strain) * (1 - relief) + 0.15 * strain + 0.02 * relief,
    P.brow: -0.9 * strain,
    P.sweat: strain,
    P.bodyH: 12.5 + 0.5 * a * strain * math.sin(u * 40),
    P.earFront: -0.3 * strain + 0.2 * relief, P.earBack: -0.3 * strain + 0.2 * relief,
    P.mouth: 0.2 * relief,
    P.stink: span(u, 6.6, 7.4) * (1 - span(u, 11.2, 12)),
    P.say: keys(u, [[0, 0], [6.5, 0], [6.6, 1], [7.1, 1], [7.3, 0], [7.5, 1], [8.6, 1], [8.9, 0]]),
    P.sayKind: u < 7.4 ? 2 : 5,
    P.tailCurl: 0.3 + 0.5 * relief,
  });
  return p;
}

/// Scrolling the phone: thumb flicks, the face lit by the screen, the odd laugh.
Pose _lounge(double t, ClipCtx c) {
  final a = c.amp;
  final p = _homeSit(c).set({
    P.phone: span(t, 0.5, 0.8),
    P.fnA1: 1.6, P.fnA2: 1.4,
    P.headRot: 0.25, P.eyeLook: 0.8, P.eyeOpen: 0.8 * blink(c.time, 5.1),
  });
  if (t < 1.0) return _settle(p, t)..[P.phone] = p[P.phone];
  final cycle = ((t - 1) / 9).floor();
  final u = (t - 1) % 9;
  final flick = math.max(0.0, math.sin(u * 5)) * (u < 5 || u > 6.8 ? 1 : 0);
  p.set({
    P.scroll: (t * 0.35) + 0.15 * flick,
    P.fnA2: 1.4 + 0.08 * flick * a,
    P.tailEndX: 25 + 3 * math.sin(t * 1.3),
  });
  if (cycle.isEven) {
    // Something funny.
    final laugh = keys(u, [[0, 0], [5.0, 0], [5.2, 1], [6.6, 1], [6.8, 0]]);
    p.set({
      P.say: laugh, P.sayKind: 0,
      P.eyeOpen: laugh > 0.5 ? 0.05 : p[P.eyeOpen],
      P.mouth: 0.5 * laugh,
      P.headRot: 0.25 - 0.3 * laugh + 0.06 * a * laugh * math.sin(u * 30),
      P.bodyH: 12.5 + 0.4 * a * laugh * math.sin(u * 30),
    });
  } else {
    // Something shocking.
    final shock = keys(u, [[0, 0], [5.0, 0], [5.1, 1], [6.2, 1], [6.5, 0]]);
    p.set({
      P.exclaim: shock, P.eyeWide: shock, P.eyeOpen: shock > 0.5 ? 1 : p[P.eyeOpen],
      P.earFront: 0.4 * shock, P.earBack: 0.4 * shock,
      P.headRot: 0.25 - 0.2 * shock,
    });
  }
  return p;
}

/// Gaming on the TV: button mashing, leaning with the game, then a win or a loss.
Pose _gaming(double t, ClipCtx c) {
  final a = c.amp;
  final p = _homeSit(c).set({
    P.tv: easeOut(span(t, 0, 0.5)),
    P.gamepad: span(t, 0.7, 1.0),
    P.fnA1: 1.95, P.fnA2: 1.1, P.ffA1: 1.75, P.ffA2: 1.45,
    P.eyeOpen: 0.9, P.eyeLook: 0.6, P.brow: -0.5,
  });
  if (t < 1.2) {
    return _settle(p, t, dur: 0.8)
      ..[P.tv] = p[P.tv]
      ..[P.gamepad] = p[P.gamepad];
  }
  final cycle = ((t - 1.2) / 10).floor();
  final u = (t - 1.2) % 10;
  final playing = u < 6 || u > 8.6;
  final ph = u * 26;
  final won = hashNoise(cycle, 5) > -0.2;
  p.set({
    P.mash: playing ? 0.5 + 0.5 * math.sin(ph) : 0,
    P.fnA2: 1.1 + (playing ? 0.1 * a * math.sin(ph) : 0),
    P.ffA2: 1.45 + (playing ? 0.1 * a * math.sin(ph + 1.7) : 0),
    P.bodyRot: -1.05 + (playing ? 0.07 * a * math.sin(u * 1.9) : 0),
    P.headRot: playing ? 0.09 * a * math.sin(u * 1.9 + 0.4) : 0,
    P.mouth: playing && (u % 3) > 1.6 ? 0.12 : 0,
    P.eyeWide: playing ? 0.5 : 0,
    P.tailCurl: 0.3 + 0.4 * math.sin(t * 5),
  });
  if (!playing) {
    final r = keys(u, [[6, 0], [6.2, 1], [8.2, 1], [8.6, 0]]);
    if (won) {
      p.set({
        P.win: r, P.say: r, P.sayKind: 3, P.exclaim: span(u, 6, 6.15) * (1 - span(u, 7.0, 7.3)),
        P.eyeOpen: 0.05, P.mouth: 0.5 * r, P.brow: 0,
        P.fnA1: 1.95 + 0.7 * r, P.ffA1: 1.75 + 0.75 * r,
        P.rootY: -4 * a * math.max(0, math.sin((u - 6) * 9)) * r,
      });
    } else {
      p.set({
        P.win: -r, P.say: r, P.sayKind: 4,
        P.headRot: 0.4 * r, P.eyeOpen: 0.4, P.brow: 0.8 * r, P.sweat: r,
        P.earFront: -0.5 * r, P.earBack: -0.5 * r,
        P.bodyRot: -1.05 + 0.15 * r,
      });
    }
  }
  return p;
}

// ---------------------------------------------------------------------------
// Cha break

/// Stand → sit for cha: hindquarters lower first, the front settles with a
/// small bounce, the tail sweeps round the paws, then the glass comes up.
Pose _sitDown(double t, ClipCtx c) {
  final a = c.amp;
  final stand = standPose();
  final sit = sitPose();
  // Back end goes down first, front follows: two blends, not one.
  final hind = easeInOut(span(t, 0.05, 0.6));
  final front = easeInOut(span(t, 0.2, 0.7));
  final p = Pose.lerp(stand, sit, front);
  for (final k in [P.bnX, P.bnY, P.bnA1, P.bnA2, P.bfX, P.bfY, P.bfA1, P.bfA2, P.legLenB, P.haunch]) {
    p[k] = stand[k] + (sit[k] - stand[k]) * hind;
  }
  // The rear can't pass through the floor while the legs fold.
  p[P.bodyY] = stand[P.bodyY] + (sit[P.bodyY] - stand[P.bodyY]) * math.max(hind * 0.8, front);
  final tail = easeInOut(span(t, 0.45, 0.95));
  for (final k in [P.tailX, P.tailY, P.tailEndX, P.tailEndY, P.tailBend, P.tailCurl]) {
    p[k] = stand[k] + (sit[k] - stand[k]) * tail;
  }
  // Settle: a tiny squash and recovery as the weight lands.
  final land = span(t, 0.62, 0.95);
  p[P.squash] = 0.05 * a * math.sin(math.pi * land);
  p[P.headY] += 1.4 * a * math.sin(math.pi * land);
  // Glance down at the glass, then the paw brings it up to the chest; the
  // glass only shows once it is in the paw, close to the body.
  final glance = easeInOut(span(t, 0.7, 0.9)) * (1 - easeInOut(span(t, 1.05, 1.35)));
  final lift = easeInOut(span(t, 0.8, 1.25));
  p.set({
    P.pinVis: 1 - span(t, 0, 0.12),
    P.headRot: 0.2 * glance,
    P.eyeLook: 0.5 * glance,
    P.fnA1: 0.05 + (_hold.a1 - 0.05) * lift,
    P.fnA2: _hold.a2 * lift,
    P.cha: span(t, 1.05, 1.2),
    P.steam: span(t, 1.2, 1.4),
    P.eyeOpen: blink(c.time),
    P.scarfPhase: c.time * 2,
  });
  return p;
}

/// The cha break itself: a 14-second cycle that never feels like a loop —
/// blow on the hot glass, careful sip, a contented "ahh", watching the street,
/// another sip, a slow happy blink. Breathing and a tail-tip twitch underneath.
Pose _teaBreak(double t, ClipCtx c) {
  final a = c.amp;
  final u = t % 14;
  final p = _teaHold(c);
  final lift = keys(u, [[0, 0], [1.0, 0], [1.6, 1], [3.6, 1], [4.1, 0], [8.4, 0], [8.9, 1], [10.2, 1], [10.6, 0], [14, 0]]);
  final blow = keys(u, [[0, 0], [1.6, 0], [1.8, 1], [2.5, 1], [2.7, 0], [14, 0]]);
  final sip = keys(u, [[0, 0], [2.8, 0], [3.05, 1], [3.5, 1], [3.7, 0], [8.9, 0], [9.15, 1], [9.9, 1], [10.1, 0], [14, 0]]);
  final ahh = keys(u, [[0, 0], [4.1, 0], [4.4, 1], [5.4, 1], [5.9, 0], [14, 0]]);
  final look = keys(u, [[0, 0], [6.0, 0], [6.4, -1], [7.4, -1], [7.8, 0.5], [8.2, 0.5], [8.4, 0], [14, 0]]);
  final slowBlink = keys(u, [[0, 1], [11.2, 1], [11.6, 0.05], [12.3, 0.05], [12.8, 1], [14, 1]]);
  final breathe = math.sin(2 * math.pi * t / 3.2);
  p.set({
    P.fnA1: _hold.a1 + (_sip.a1 - _hold.a1) * lift,
    P.fnA2: _hold.a2 + (_sip.a2 - _hold.a2) * lift,
    P.chaTilt: 0.55 * sip,
    P.blow: blow,
    P.steam: 1 - 0.3 * sip,
    P.mouth: 0.18 * blow + 0.22 * ahh,
    P.headRot: -0.15 * sip * a - 0.06 * ahh + 0.18 * look,
    P.headY: -45 + 0.8 * ahh,
    P.eyeLook: look,
    P.eyeOpen: sip > 0.3 ? 0.05 : (ahh > 0.3 ? 0.35 : blink(c.time, 4.1) * slowBlink),
    P.earFront: 0.2 * sip - 0.12 * ahh + 0.5 * keys(u, [[0, 0], [7.0, 0], [7.08, 1], [7.25, 0], [14, 0]]),
    P.earBack: 0.2 * sip - 0.12 * ahh,
    P.bodyH: 12.5 + 0.35 * breathe - 0.5 * ahh,
    P.squash: 0.012 * a * breathe,
    P.tailCurl: 0.3 + 0.25 * math.max(0, math.sin(t * 2.1)) + 0.2 * ahh,
    P.tailEndX: 25 + 1.5 * math.sin(t * 0.9),
  });
  return p;
}

// ---------------------------------------------------------------------------
// Places from "More places". Each scene enters from standing on its own
// (props fade in) and runs as a long cycle, so it never looks like a loop.

/// Standing, a little towards the left so the scene has room on the right.
Pose _placeStand(ClipCtx c) => standPose().set({
      P.pinVis: 0, P.rootX: -6,
      P.eyeOpen: blink(c.time, 4.1),
      P.scarfPhase: c.time * 2,
    });

/// A soft breath and tail sway underneath every scene.
void _alive(Pose p, double t, ClipCtx c, {double tail = 1}) {
  final breathe = math.sin(2 * math.pi * t / 3.4);
  p[P.bodyH] += 0.3 * breathe;
  p[P.headY] += 0.35 * breathe * c.amp;
  p[P.tailCurl] += 0.18 * tail * math.sin(t * 1.7);
  p[P.tailEndX] += 1.4 * tail * math.sin(t * 0.9);
}

/// The fish stall: inspect, "কত?", shock at the price, "না না!", a deal,
/// then a happy pose with the fish in a bag. 14-second cycle.
Pose _bazar(double t, ClipCtx c) {
  final a = c.amp;
  final p = _placeStand(c).set({P.stall: easeOut(span(t, 0, 0.6)), P.stallFish: 1});
  final u = t % 14;
  _alive(p, t, c);
  final sniff = keys(u, [[0, 0], [0.4, 1], [1.8, 1], [2.2, 0], [14, 0]]);
  final point = keys(u, [[0, 0], [2.2, 0], [2.6, 1], [3.6, 1], [4.0, 0], [14, 0]]);
  final shock = keys(u, [[0, 0], [3.8, 0], [3.9, 1], [5.0, 1], [5.3, 0], [14, 0]]);
  final shake = keys(u, [[0, 0], [5.2, 0], [5.4, 1], [6.9, 1], [7.1, 0], [14, 0]]);
  final deal = keys(u, [[0, 0], [7.3, 0], [7.6, 1], [8.9, 1], [9.2, 0], [14, 0]]);
  final carry = keys(u, [[0, 0], [9.0, 0], [9.6, 1], [13.2, 1], [13.8, 0], [14, 0]]);
  p.set({
    // Lean in and sniff the fish.
    P.headX: 25 + 4 * sniff - 2 * shock, P.headY: p[P.headY] + 2.5 * sniff - 1.5 * shock,
    P.headRot: 0.2 * sniff + 0.22 * shake * math.sin(u * 15) - 0.1 * carry,
    P.bodyRot: 0.06 * sniff,
    P.mouth: 0.08 * sniff * (0.5 + 0.5 * math.sin(u * 22)) + 0.3 * point + 0.25 * shake + 0.2 * deal + 0.15 * carry,
    // Point at the fish while asking; later the paw holds up the bag.
    P.fnA1: 1.45 * point + 1.3 * carry, P.fnA2: 0.25 * point + 0.25 * carry,
    P.eyeLook: 0.9 * (sniff + point) - 0.3 * shake,
    P.eyeWide: shock, P.exclaim: shock,
    P.eyeOpen: carry > 0.5 ? 0.06 : (shock > 0.3 ? 1 : blink(c.time, 4.1)),
    P.earFront: 0.45 * shock - 0.2 * shake + 0.25 * carry,
    P.earBack: 0.45 * shock - 0.2 * shake + 0.25 * carry,
    P.brow: 0.7 * shake,
    P.rootY: -3 * a * math.sin(math.pi * span(u, 3.85, 4.15)),
    // The fish leaves the stall and appears in the bag.
    P.stallFish: 1 - span(u, 9.0, 9.4) * (1 - span(u, 13.5, 13.9)),
    P.bag: carry,
    P.tailCurl: 0.6 + 0.6 * carry * math.max(0, math.sin(u * 6)),
  });
  const says = <List<double>>[[2.4, 3.7, 6], [5.3, 7.0, 7], [7.5, 9.0, 8]];
  for (final s in says) {
    final v = keys(u, [[0, 0], [s[0], 0], [s[0] + 0.15, 1], [s[1], 1], [s[1] + 0.2, 0], [14, 0]]);
    if (v > p[P.say]) {
      p[P.say] = v;
      p[P.sayKind] = s[2];
    }
  }
  return p;
}

/// Eating out: napkin tucked in, a plate of biryani, nom nom. When the plate
/// is empty: a burp, a belly pat, "আরেকটা!" and a fresh plate arrives.
Pose _feast(double t, ClipCtx c) {
  final a = c.amp;
  final p = _homeSit(c).set({
    P.home: 0, P.shadow: 0.85,
    P.napkin: easeOut(span(t, 0.3, 0.8)),
    P.biryani: easeOut(span(t, 0, 0.5)),
  });
  if (t < 1.0) {
    final s = _settle(p, t);
    s[P.home] = 0;
    s[P.napkin] = p[P.napkin];
    s[P.biryani] = p[P.biryani];
    return s;
  }
  final m = (t - 1) % 52;
  final eating = m < 40 || m > 49;
  final u = m % 4.5;
  final lean = eating ? keys(u, [[0, 0], [0.5, 1], [1.3, 1], [1.7, 0]]) : 0.0;
  final nib = eating && u > 0.5 && u < 1.3 ? math.max(0.0, math.sin((u - 0.5) * 18)) : 0.0;
  final chew = eating && u > 1.6 && u < 4.0 ? 0.5 + 0.5 * math.sin(u * 16) : 0.0;
  final full = keys(m, [[0, 0], [40, 0], [40.4, 1], [45.8, 1], [46.2, 0], [52, 0]]);
  final pat = full * math.max(0.0, math.sin((m - 40) * 7));
  final more = keys(m, [[0, 0], [46.0, 0], [46.3, 1], [48.0, 1], [48.3, 0], [52, 0]]);
  final burp = keys(m, [[0, 0], [41.0, 0], [41.15, 1], [42.4, 1], [42.6, 0], [52, 0]]);
  p.set({
    P.bite: m < 48 ? clamp01(m / 40) : 1 - easeOut(span(m, 48, 48.7)),
    P.bodyRot: -1.05 + 0.4 * lean - 0.12 * full, P.bodyX: -1 + 2 * lean,
    P.bodyH: 12.5 + 1.3 * full,
    P.headX: 6 + 9 * lean, P.headY: -45 + 21 * lean + 1.5 * nib * a, P.headRot: 0.55 * lean - 0.1 * full,
    P.eyeOpen: lean > 0.5 ? 0.6 : (chew > 0 || full > 0.5 ? 0.05 : blink(c.time, 4.3)),
    P.mouth: 0.3 * nib + 0.22 * chew + 0.5 * burp + 0.35 * more,
    P.earFront: 0.1 * chew + 0.3 * more, P.earBack: 0.1 * chew + 0.3 * more,
    // Belly pat with the near paw, then the paw goes up for another plate.
    P.fnA1: 0.05 + 0.75 * full + 2.6 * more, P.fnA2: (1.2 + 0.25 * pat) * full + 0.3 * more,
    P.squash: 0.07 * a * span(m, 41.0, 41.1) * (1 - span(m, 41.1, 41.35)),
    P.exclaim: span(m, 48.1, 48.25) * (1 - span(m, 48.9, 49.2)),
    P.tailCurl: 0.3 + 0.35 * math.max(0, math.sin(t * 2.4)) + 0.4 * full,
  });
  if (burp > p[P.say]) {
    p[P.say] = burp;
    p[P.sayKind] = 1;
  }
  if (more > p[P.say]) {
    p[P.say] = more;
    p[P.sayKind] = 10;
  }
  return p;
}

/// The bus stop: wait, look down the road, yawn. A bus! It roars past
/// without stopping. "আরে!" A slump, and back to waiting. 16-second cycle.
Pose _busWait(double t, ClipCtx c) {
  final a = c.amp;
  final p = _placeStand(c).set({P.busStop: easeOut(span(t, 0, 0.6)), P.rootX: 2});
  final u = t % 16;
  _alive(p, t, c);
  final look = keys(u, [[0, 0], [0.6, 1], [3.2, 1], [3.6, 0], [14.8, 0], [15.4, 1], [16, 1]]);
  final yawn = keys(u, [[0, 0], [4.0, 0], [4.5, 1], [5.4, 1], [5.9, 0], [16, 0]]);
  final hear = keys(u, [[0, 0], [6.2, 0], [6.35, 1], [7.0, 1], [7.4, 0], [16, 0]]);
  final bus = span(u, 6.8, 9.2);
  final gust = keys(u, [[0, 0], [7.5, 0], [7.7, 1], [8.6, 1], [9.0, 0], [16, 0]]);
  final are = keys(u, [[0, 0], [9.2, 0], [9.45, 1], [11.0, 1], [11.3, 0], [16, 0]]);
  final slump = keys(u, [[0, 0], [11.2, 0], [11.8, 1], [14.4, 1], [15.0, 0], [16, 0]]);
  final tap = math.max(0.0, math.sin(u * 9)) * (u < 3.6 || u > 15 ? 1 : 0);
  p.set({
    P.busX: bus,
    P.quick: u > 6.7 && u < 9.3 ? 1 : 0,
    // Looking back down the road for the bus.
    P.headRot: -0.22 * look - 0.15 * gust + 0.05 * slump,
    P.eyeLook: -1 * look + 0.6 * hear - 0.8 * gust,
    P.headX: 25 - 2 * look, P.headY: p[P.headY] + 3 * slump,
    P.eyeOpen: yawn > 0.4 ? 0.05 : (gust > 0.3 ? 0.25 : (slump > 0.5 ? 0.55 : blink(c.time, 4.1))),
    P.mouth: 0.55 * yawn + 0.4 * are,
    P.eyeWide: hear, P.exclaim: hear,
    P.earFront: 0.4 * hear - 0.3 * slump, P.earBack: 0.4 * hear - 0.3 * slump,
    P.earFlat: 0.8 * gust,
    P.scarfFlow: 0.2 + 0.8 * gust, P.scarfPhase: c.time * (2 + 14 * gust),
    P.dust: gust,
    P.rootY: -5 * a * math.sin(math.pi * span(u, 6.3, 6.75)),
    P.bodyRot: -0.06 * gust + 0.05 * slump,
    P.bodyH: p[P.bodyH] - 0.6 * slump,
    // Waves a paw after the bus.
    P.fnA1: 2.5 * are, P.fnA2: (0.3 + 0.35 * math.sin(u * 14)) * are,
    P.brow: 0.8 * are - 0.4 * slump,
    // Tapping a back paw while waiting.
    P.bnA1: -0.12 * tap * a,
    P.tailCurl: 0.6 + 0.4 * math.sin(u * 3) * (1 - slump) - 0.3 * slump,
  });
  if (are > p[P.say]) {
    p[P.say] = are;
    p[P.sayKind] = 9;
  }
  return p;
}

/// The park: stalk a butterfly, pounce (miss!), sunbathe, then the butterfly
/// lands on the cat's nose… "হাঁচ্চু!" 20-second cycle.
Pose _park(double t, ClipCtx c) {
  final a = c.amp;
  final u = t % 20;
  final crouch = standPose().set({
    P.pinVis: 0, P.rootX: -8,
    P.bodyY: -23, P.bodyRot: 0.08, P.headX: 26, P.headY: -37, P.headRot: -0.12,
    P.legLen: 0.78, P.legLenB: 0.8, P.fnY: -19, P.ffY: -19, P.bnY: -20, P.bfY: -20,
    P.eyeLook: 0.8, P.eyeOpen: 1, P.eyeWide: 0.5,
    P.earFront: 0.25, P.earBack: 0.25,
    P.scarfPhase: c.time * 2,
  });
  final sit = sitPose().set({P.pinVis: 0, P.rootX: -6, P.eyeOpen: blink(c.time, 4.3), P.scarfPhase: c.time * 2});
  // Sunbathing: face up to the sun, eyes shut, a little smile.
  final lie = sit.copy().set({
    P.headX: 4, P.headY: -46, P.headRot: -0.38, P.eyeOpen: 0, P.mouth: 0.14,
    P.earFront: -0.1, P.earBack: -0.05, P.tailCurl: 0.5,
  });

  // Which body pose: crouch, sunbathe, sit, crouch again.
  Pose body;
  if (u < 7.0) {
    body = crouch;
  } else if (u < 8.2) {
    body = Pose.lerp(crouch, lie, easeInOut(span(u, 7.0, 8.2)));
  } else if (u < 12.6) {
    body = lie;
  } else if (u < 13.6) {
    body = Pose.lerp(lie, sit, easeInOut(span(u, 12.6, 13.6)));
  } else if (u < 19.0) {
    body = sit;
  } else {
    body = Pose.lerp(sit, crouch, easeInOut(span(u, 19.0, 20.0)));
  }
  final p = body.copy();
  p.set({P.grass: easeOut(span(t, 0, 0.6)), P.sun: easeOut(span(t, 0.2, 0.9))});

  // Butterfly flight: wandering, escape, return to the nose, scared off.
  final nose = (dx: p[P.headX] + p[P.rootX] + 13, dy: p[P.headY] + p[P.rootY] - 3);
  double fx, fy, fv = 1;
  if (u < 5.4) {
    fx = 34 + 9 * math.sin(u * 1.3) + 4 * math.sin(u * 3.1);
    fy = -46 + 7 * math.sin(u * 1.9 + 1);
  } else if (u < 7.0) {
    final e = easeOut(span(u, 5.4, 7.0));
    fx = 34 + 9 * math.sin(5.4 * 1.3) + 4 * math.sin(5.4 * 3.1) + 18 * e;
    fy = -46 + 7 * math.sin(5.4 * 1.9 + 1) - 44 * e;
    fv = 1 - span(u, 6.4, 7.0);
  } else if (u < 13.8) {
    fx = 60;
    fy = -90;
    fv = 0;
  } else if (u < 15.6) {
    final e = easeInOut(span(u, 13.8, 15.6));
    fx = 58 + (nose.dx - 58) * e + 4 * math.sin(u * 5) * (1 - e);
    fy = -80 + (nose.dy + 80) * e;
    fv = span(u, 13.8, 14.3);
  } else if (u < 17.3) {
    fx = nose.dx;
    fy = nose.dy;
  } else {
    final e = easeOut(span(u, 17.3, 18.6));
    fx = nose.dx + 30 * e;
    fy = nose.dy - 46 * e;
    fv = 1 - span(u, 18.1, 18.6);
  }
  p.set({P.fly: fv, P.flyX: fx, P.flyY: fy});

  if (u < 7.0) {
    // Stalk: eyes follow it, a bottom wiggle, then the pounce.
    final wiggle = keys(u, [[0, 0], [3.6, 0], [3.9, 1], [4.9, 1], [5.1, 0], [7, 0]]);
    final pounce = span(u, 5.1, 5.9);
    final hop = math.sin(math.pi * pounce);
    p.set({
      P.eyeLook: (fx - nose.dx).clamp(-12.0, 12.0) / 12,
      P.headRot: -0.12 - 0.012 * (nose.dy - fy).clamp(-10.0, 25.0),
      P.bodyRot: 0.08 + 0.05 * a * wiggle * math.sin(u * 22),
      P.tailCurl: 0.6 + 0.3 * math.sin(u * 4) + 0.3 * wiggle * math.sin(u * 22),
      P.rootY: -14 * a * hop, P.rootX: -8 + 12 * easeInOut(pounce) * (1 - span(u, 6.0, 7.0)),
      P.fnA1: 2.3 * hop, P.ffA1: 2.1 * hop, P.fnA2: -0.4 * hop, P.ffA2: -0.4 * hop,
      P.bnA1: -0.6 * hop, P.bfA1: -0.6 * hop,
      P.quick: u > 3.6 && u < 6.4 ? 1 : 0,
      P.question: span(u, 6.0, 6.2) * (1 - span(u, 6.8, 7.0)),
    });
  } else if (u < 12.6) {
    // Sunbathing: slow tail, a happy "ahh…".
    final ahh = keys(u, [[0, 0], [8.8, 0], [9.0, 1], [10.6, 1], [10.9, 0], [20, 0]]);
    p.set({
      P.say: ahh, P.sayKind: 5,
      P.tailEndX: p[P.tailEndX] + 3 * math.sin(u * 1.2),
      P.bodyH: p[P.bodyH] + 0.4 * math.sin(u * 1.8),
    });
  } else if (u >= 13.6 && u < 19.0) {
    // The butterfly lands on the nose: cross-eyed, a tickle building, sneeze.
    final land = span(u, 15.4, 15.6);
    final build = keys(u, [[0, 0], [15.8, 0], [16.3, 0.5], [16.6, 0.3], [17.1, 1], [17.2, 0], [20, 0]]);
    final sneeze = keys(u, [[0, 0], [17.15, 0], [17.25, 1], [17.6, 0.6], [18.6, 0], [20, 0]]);
    final say = keys(u, [[0, 0], [17.2, 0], [17.3, 1], [18.5, 1], [18.8, 0], [20, 0]]);
    p.set({
      P.eyeLook: 0.4 + 0.6 * land,
      P.eyeOpen: build > 0.6 ? 0.2 : (sneeze > 0.5 ? 0.05 : 1),
      P.eyeWide: 0.6 * land * (1 - sneeze),
      P.headY: p[P.headY] + 1.5 * build - 3 * sneeze * a,
      P.headRot: -0.12 * build + 0.3 * sneeze * a,
      P.mouth: 0.15 * build + 0.5 * sneeze,
      P.squash: 0.06 * a * sneeze,
      P.earFront: 0.3 * land - 0.3 * sneeze, P.earBack: 0.3 * land - 0.3 * sneeze,
      P.say: say, P.sayKind: 11,
      P.quick: u > 17.1 && u < 18.7 ? 1 : 0,
    });
  }
  return p;
}
