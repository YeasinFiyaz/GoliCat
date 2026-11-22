import 'dart:math' as math;
import 'dart:typed_data';

/// Every drawable parameter of GoliCat and its props, as one flat vector.
/// Because a pose is just numbers, any two poses can be blended — that is how
/// every transition (sit, hop, skid, tuck in…) stays smooth and in character.
///
/// Coordinates are "cat units" (about 0.8 dp each at medium size), facing
/// right, origin on the ground under the cat, y pointing down.
enum P {
  facing, rootX, rootY, squash, shadow,
  bodyX, bodyY, bodyRot, bodyLen, bodyH, haunch,
  headX, headY, headRot,
  earFront, earBack, eyeOpen, eyeWide, eyeLook, brow, mouth,
  fnX, fnY, fnA1, fnA2,
  ffX, ffY, ffA1, ffA2,
  bnX, bnY, bnA1, bnA2,
  bfX, bfY, bfA1, bfA2,
  legLen, legLenB,
  tailX, tailY, tailEndX, tailEndY, tailBend, tailCurl,
  scarfNeck, scarfFlow, scarfPhase, scarfFace,
  cha, chaX, chaY, chaTilt, steam,
  mapVis, mapOpen, mapRot,
  glassesFace, glassesMon,
  office, chairX, enterFlash, keyFlash, screenText, fish, fishX, fishY, monWobble,
  home, blanket, blanketHead, bubble, zzz, dream, dreamKind, kick,
  pinVis, pinWobble,
  speedLines, dust, exclaim, question, sweat, impact, time,
  // Study desk (education) and the hangout bench.
  desk, pencil, write, lamp,
  bench, headphones, notes, beat,
  // Home life: bucket bath, rice and fish, the litter tray, the phone, the game.
  bucket, mug, splash, foam,
  plate, bite,
  litter, paper, stink,
  phone, scroll,
  tv, gamepad, mash, win,
  say, sayKind,
  // Polish: ears pressed flat by the wind; blowing on hot cha.
  earFlat, blow,
  // Places from "More places": the fish stall, eating out, the bus stop, the park.
  stall, stallFish, bag,
  napkin, biryani,
  busStop, busX,
  grass, sun, fly, flyX, flyY,
  // 1 while something fast is on screen (a bus, a pounce): draw at full frame rate.
  quick,
}

/// Words the cat can say ([P.sayKind] indexes this list; only ever append).
const homeSayings = ['ha ha', 'burp!', 'plop', 'yesss!', 'nooo', 'ahh…',
    'কত?', 'না না!', 'ঠিক আছে', 'আরে!', 'আরেকটা!', 'হাঁচ্চু!'];

class Pose {
  Pose._(this.v);
  factory Pose.zero() => Pose._(Float64List(P.values.length));
  final Float64List v;

  double operator [](P p) => v[p.index];
  void operator []=(P p, double value) => v[p.index] = value;

  Pose copy() => Pose._(Float64List.fromList(v));

  /// Linear blend (t=0 → a, t=1 → b).
  static Pose lerp(Pose a, Pose b, double t) {
    final out = Float64List(a.v.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = a.v[i] + (b.v[i] - a.v[i]) * t;
    }
    // Phases/clocks shouldn't rewind during a blend.
    out[P.time.index] = b.v[P.time.index];
    out[P.scarfPhase.index] = b.v[P.scarfPhase.index];
    return Pose._(out);
  }

  /// Applies several values at once: `pose.set({P.headY: -40, P.eyeOpen: 1})`.
  Pose set(Map<P, double> values) {
    values.forEach((k, val) => v[k.index] = val);
    return this;
  }

  /// Adds offsets: `pose.add({P.headY: 2})`.
  Pose add(Map<P, double> values) {
    values.forEach((k, val) => v[k.index] += val);
    return this;
  }

  /// Blends just the listed parameters toward [other].
  Pose blendFrom(Pose other, double t, Iterable<P> keys) {
    for (final k in keys) {
      v[k.index] = v[k.index] + (other.v[k.index] - v[k.index]) * t;
    }
    return this;
  }
}

// ---------------------------------------------------------------------------
// Easing + keyframe helpers used by the clips.

double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double easeInOut(double x) {
  x = clamp01(x);
  return x * x * (3 - 2 * x);
}

double easeOut(double x) {
  x = clamp01(x);
  return 1 - (1 - x) * (1 - x);
}

double easeIn(double x) {
  x = clamp01(x);
  return x * x;
}

/// Back-out overshoot ("boing").
double easeBack(double x) {
  x = clamp01(x);
  const c = 1.9;
  return 1 + (c + 1) * math.pow(x - 1, 3) + c * math.pow(x - 1, 2);
}

/// Progress of [t] through [a, b] mapped to 0..1.
double span(double t, double a, double b) => clamp01((t - a) / (b - a));

/// Piecewise keyframes: [[time, value], …] with smooth easing between keys.
double keys(double t, List<List<double>> k) {
  if (t <= k.first[0]) return k.first[1];
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i][0]) {
      final a = k[i - 1], b = k[i];
      final u = easeInOut((t - a[0]) / (b[0] - a[0]));
      return a[1] + (b[1] - a[1]) * u;
    }
  }
  return k.last[1];
}

/// Small deterministic hash noise in [-1, 1].
double hashNoise(int a, [int b = 0]) {
  var h = a * 374761393 + b * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return ((h & 0xffff) / 0xffff) * 2 - 1;
}
