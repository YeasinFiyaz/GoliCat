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
}

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
  ClipId.tuckIn: ClipSpec(2.3, 'Home. Yaaawn…'),
  ClipId.sleep: ClipSpec(null, 'বাসায় ঘুমাচ্ছি · Asleep at home'),
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

/// Sitting on the hangout bench with headphones on.
Pose vibePose() => sitPose().set({
      P.bench: 1, P.pinVis: 0, P.shadow: 0.55,
      P.rootY: -11,
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
  final a = c.amp;
  final ph = 2 * math.pi * t * 3.3 * c.cadence;
  final p = standPose();
  p.set({
    P.pinVis: 0,
    P.bodyX: 2, P.bodyRot: 0.1, P.bodyLen: 23 + 1.5 * a * math.sin(ph),
    P.bodyY: -27 - 2 * a * math.sin(2 * ph).abs(),
    P.headX: 31, P.headY: -39 - 1.2 * a * math.sin(2 * ph).abs(), P.headRot: 0.15,
    P.earFront: 1.05, P.earBack: 1.1, P.eyeOpen: 0.8, P.brow: -0.5,
    P.fnX: 15, P.ffX: 11, P.bnX: -12, P.bfX: -16,
    P.fnA1: 0.85 * a * math.sin(ph), P.fnA2: -0.6 * a * math.max(0, math.cos(ph)),
    P.ffA1: 0.85 * a * math.sin(ph + 0.5), P.ffA2: -0.6 * a * math.max(0, math.cos(ph + 0.5)),
    P.bnA1: 0.85 * a * math.sin(ph + math.pi), P.bnA2: 0.6 * a * math.max(0, -math.cos(ph)),
    P.bfA1: 0.85 * a * math.sin(ph + math.pi + 0.5), P.bfA2: 0.6 * a * math.max(0, -math.cos(ph + 0.5)),
    P.tailX: -21, P.tailY: -30, P.tailEndX: -22, P.tailEndY: -5,
    P.tailBend: 2 + math.sin(ph), P.tailCurl: 0.1,
    P.scarfFlow: 1, P.scarfPhase: c.time * 16,
    P.speedLines: a, P.rootY: -1.5 * a * math.sin(ph).abs(), P.shadow: 0.9,
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
      final p = Pose.lerp(standPose(), sitPose(), easeInOut(span(t, 0, 0.6)));
      final pull = easeInOut(span(t, 0.65, 1.3));
      p.set({
        P.cha: span(t, 0.7, 0.9),
        P.steam: span(t, 1.0, 1.4),
        P.fnA1: 0.05 + (_hold.a1 - 0.05) * pull,
        P.fnA2: _hold.a2 * pull,
        P.eyeOpen: blink(c.time),
        P.scarfPhase: c.time * 2,
      });
      return p;

    case ClipId.tea:
      final u = t % 5;
      final p = _teaHold(c);
      final lift = keys(u, [[0, 0], [1.4, 0], [2.0, 1], [3.1, 1], [3.6, 0], [5, 0]]);
      final sip = keys(u, [[0, 0], [2.0, 0], [2.3, 1], [3.0, 1], [3.3, 0], [5, 0]]);
      p.set({
        P.fnA1: _hold.a1 + (_sip.a1 - _hold.a1) * lift,
        P.fnA2: _hold.a2 + (_sip.a2 - _hold.a2) * lift,
        P.chaTilt: 0.55 * sip,
        P.headRot: -0.15 * sip * a,
        P.eyeOpen: sip > 0.3 ? 0.05 : (u > 3.6 ? 0.45 : blink(c.time, 4.1)),
        P.earFront: 0.2 * sip, P.earBack: 0.2 * sip,
        P.mouth: u > 3.6 && u < 4.4 ? 0.25 : 0,
        P.tailCurl: 0.3 + 0.3 * math.max(0, math.sin(t * 3)),
      });
      return p;

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
      final p = _vibing(t, c);
      final on = span(t, 0, 0.2) * (1 - span(t, 2.0, 2.4));
      final beat = (math.sin(2 * math.pi * t * 2.2)).abs();
      p.set({
        P.rootY: -11 - 5 * a * beat * on,
        P.squash: 0.12 * a * (1 - beat) * on,
        P.headRot: 0.22 * a * math.sin(2 * math.pi * t * 2.2) * on,
        P.eyeOpen: 0.05, P.mouth: 0.4 * on,
        P.earFront: 0.4 * beat * on, P.earBack: 0.4 * beat * on,
        P.fnA1: 0.05 + 2.2 * on * (0.5 + 0.5 * math.sin(2 * math.pi * t * 2.2)),
        P.ffA1: 0.05 + 2.2 * on * (0.5 + 0.5 * math.sin(2 * math.pi * t * 2.2 + math.pi)),
        P.notes: 1 + on, P.exclaim: span(t, 0, 0.1) * (1 - span(t, 0.5, 0.7)),
      });
      return p;

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

/// Head bobbing to the beat, paw tapping, tail swaying; notes drift up.
Pose _vibing(double t, ClipCtx c) {
  final a = c.amp;
  final bpm = 2.0; // beats per second
  final ph = 2 * math.pi * t * bpm;
  final beat = math.max(0.0, math.sin(ph));
  final p = vibePose();
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
