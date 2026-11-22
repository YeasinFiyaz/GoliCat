import 'dart:math' as math;

import '../tracking/activity_engine.dart';
import 'clips.dart';
import 'pose.dart';

/// Turns [CatMode] changes into a sequence of clips with visible transitions:
/// tea → stash the glass → catch up; fast → skid; arriving at the office →
/// hop onto the chair; home → yawn and tuck in, and so on.
///
/// It knows nothing about GPS or maps, so it can be tested and demoed alone.
class CatDirector {
  CatDirector({this.reducedMotion = false, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  bool reducedMotion;

  /// Wall clock: picks the home activity, so every screen showing this cat
  /// (the app, the trip service, a live-share viewer) agrees on it.
  final DateTime Function() clock;

  /// Home activities other than sleeping.
  static const homeLife = [ClipId.bath, ClipId.eat, ClipId.potty, ClipId.lounge, ClipId.gaming];
  static const homeActivities = [ClipId.sleep, ...homeLife];
  static bool isHomeLife(ClipId c) => homeLife.contains(c);

  /// What the cat does at home during the minute containing [now]: a shuffled
  /// order that never repeats an activity twice in a row. At night it sleeps.
  static ClipId homeActivityAt(DateTime now) {
    if (now.hour >= 23 || now.hour < 7) return ClipId.sleep;
    final slot = now.millisecondsSinceEpoch ~/ 60000;
    final n = homeActivities.length;
    return _homeOrder(slot ~/ n)[slot % n];
  }

  static List<ClipId> _homeOrder(int block) {
    List<ClipId> shuffled(int b) => [...homeActivities]..shuffle(math.Random(b * 7919 + 13));
    final order = shuffled(block);
    if (order.first == shuffled(block - 1).last) {
      final first = order[0];
      order[0] = order[1];
      order[1] = first;
    }
    return order;
  }

  /// Seconds an activity has to run before the minute can change it.
  static const homeMinStay = 20.0;

  /// True while the cat is settled in a slow loop (asleep, sipping cha, at a
  /// desk…): nothing quick is on screen, so it can be drawn at a lower frame
  /// rate to save battery. Walking, running, every transition, a turn and a
  /// tap reaction are never calm.
  bool get calm =>
      clipSpecs[_clip]!.loops &&
      _clip != ClipId.walk &&
      _clip != ClipId.fast &&
      _clipT > 1.5 &&
      _queue.isEmpty &&
      !(_blendFrom != null && _blendT < 1) &&
      _boop >= 1.1 &&
      (_facing.abs() - 1).abs() < 0.001;

  /// Lets the next home activity start now instead of after [homeMinStay]
  /// (the animation preview's "Next home activity").
  /// Only takes effect once the cat is settled in a home activity, so a
  /// transition already playing is never cut short.
  void skipHomeStay() => _skipStay = true;
  bool _skipStay = false;

  ClipId _target() => _mode == CatMode.atHome ? homeActivityAt(clock()) : loopFor(_mode);
  double _boop = 99;

  CatMode _mode = CatMode.starting;
  ClipId _clip = ClipId.idle;
  double _clipT = 0;
  final List<ClipId> _queue = [];
  double _time = 0;

  Pose? _blendFrom;
  double _blendT = 1;
  double _blendDur = 0.22;

  double _facing = 1;
  double _facingTarget = 1;
  double cadence = 1;

  /// Every clip that has played (for the trip comic).
  final List<ClipId> history = [];
  void Function(ClipId)? onClipStart;

  Pose _last = standPose();

  ClipId get clip => _clip;
  CatMode get mode => _mode;
  Pose get pose => _last;
  String get label => clipSpecs[_clip]!.label;
  double get time => _time;

  static ClipId loopFor(CatMode m) => switch (m) {
        CatMode.starting || CatMode.idle => ClipId.idle,
        CatMode.waiting => ClipId.tea,
        CatMode.walking => ClipId.walk,
        CatMode.fast => ClipId.fast,
        CatMode.lost => ClipId.lost,
        CatMode.atWork => ClipId.typing,
        CatMode.atHome => ClipId.sleep,
        CatMode.studying => ClipId.study,
        CatMode.hangingOut => ClipId.vibe,
        CatMode.jammed => ClipId.jam,
      };

  /// The loop "family" a clip belongs to (what we are coming out of).
  static ClipId baseOf(ClipId c) => switch (c) {
        ClipId.skid || ClipId.batPin || ClipId.foldMap || ClipId.idle => ClipId.idle,
        ClipId.sitDown || ClipId.tea => ClipId.tea,
        ClipId.stashTea || ClipId.catchUp || ClipId.walk || ClipId.leaveOffice || ClipId.wakeUp => ClipId.walk,
        ClipId.fast => ClipId.fast,
        ClipId.unfoldMap || ClipId.lost => ClipId.lost,
        ClipId.hopOnChair || ClipId.typing || ClipId.fishGag => ClipId.typing,
        ClipId.tuckIn || ClipId.sleep || ClipId.grumpy => ClipId.sleep,
        ClipId.sitAtDesk || ClipId.study || ClipId.stuckGag || ClipId.closeBook => ClipId.study,
        ClipId.headphonesOn || ClipId.vibe || ClipId.danceGag || ClipId.headphonesOff => ClipId.vibe,
        ClipId.jamOn || ClipId.jam || ClipId.jamDance || ClipId.jamOff => ClipId.jam,
        ClipId.tuckInHome => ClipId.sleep,
        ClipId.homeStroll || ClipId.homeWake => ClipId.lounge,
        ClipId.leaveHome => ClipId.walk,
        ClipId.bath || ClipId.eat || ClipId.potty || ClipId.lounge || ClipId.gaming => c,
      };

  /// The transition plan from the current base loop into [target]'s loop.
  /// At home, [home] names the activity to go to (sleep when not given).
  static List<ClipId> plan(ClipId fromBase, CatMode target, {ClipId? home}) {
    final to = target == CatMode.atHome ? (home ?? ClipId.sleep) : loopFor(target);
    if (fromBase == to) return [to];
    final staying = target == CatMode.atHome && (fromBase == ClipId.sleep || isHomeLife(fromBase));
    final out = <ClipId>[];
    // Leaving.
    switch (fromBase) {
      case ClipId.tea:
        out.add(ClipId.stashTea);
      case ClipId.lost:
        out.add(ClipId.foldMap);
      case ClipId.typing:
        out.add(ClipId.leaveOffice);
      case ClipId.sleep:
        out.add(staying ? ClipId.homeWake : ClipId.wakeUp);
      case ClipId.study:
        out.add(ClipId.closeBook);
      case ClipId.bath || ClipId.eat || ClipId.potty || ClipId.lounge || ClipId.gaming:
        out.add(staying ? ClipId.homeStroll : ClipId.leaveHome);
      case ClipId.vibe:
        out.add(ClipId.headphonesOff);
      case ClipId.jam:
        out.add(ClipId.jamOff);
      case ClipId.fast:
        if (to == ClipId.walk || to == ClipId.idle || to == ClipId.tea) out.add(ClipId.skid);
      default:
        break;
    }
    // Entering.
    switch (to) {
      case ClipId.tea:
        out.add(ClipId.sitDown);
      case ClipId.lost:
        out.add(ClipId.unfoldMap);
      case ClipId.typing:
        out.add(ClipId.hopOnChair);
      case ClipId.sleep:
        out.add(staying ? ClipId.tuckInHome : ClipId.tuckIn);
      case ClipId.bath || ClipId.eat || ClipId.potty || ClipId.lounge || ClipId.gaming:
        if (!staying) out.add(ClipId.homeStroll);
      case ClipId.study:
        out.add(ClipId.sitAtDesk);
      case ClipId.vibe:
        out.add(ClipId.headphonesOn);
      case ClipId.jam:
        out.add(ClipId.jamOn);
      case ClipId.walk:
        if (fromBase == ClipId.tea) out.add(ClipId.catchUp);
      default:
        break;
    }
    out.add(to);
    return out;
  }

  /// Sets the travel direction on screen: positive = right.
  void setScreenHeading(double dx) {
    if (dx.abs() < 0.25) return;
    _facingTarget = dx > 0 ? 1 : -1;
  }

  void setMode(CatMode m) {
    if (m == _mode) return;
    _mode = m;
    final spec = clipSpecs[_clip]!;
    if (spec.loops || spec.gag) {
      _replan();
    }
    // Otherwise the running one-shot finishes first, then we replan.
  }

  void _replan() {
    _queue
      ..clear()
      ..addAll(plan(baseOf(_clip), _mode, home: _target()));
    _next();
  }

  void _next() {
    if (_queue.isEmpty) return;
    final c = _queue.removeAt(0);
    if (c == _clip && clipSpecs[c]!.loops) return;
    _start(c);
  }

  void _start(ClipId c) {
    _blendFrom = _last.copy();
    _blendT = 0;
    // Home changes glide a little slower so props fade instead of popping.
    _blendDur = homeActivities.contains(c) || c == ClipId.homeStroll || c == ClipId.leaveHome || c == ClipId.tuckInHome ? 0.6 : 0.22;
    _clip = c;
    _clipT = 0;
    history.add(c);
    onClipStart?.call(c);
  }

  /// Tap on the cat. Returns true if it reacted.
  bool tap() {
    switch (_clip) {
      case ClipId.idle:
      case ClipId.tea:
        if (_clip == ClipId.tea) {
          // Sitting with cha: stand briefly to swat, then settle again.
          _queue
            ..clear()
            ..addAll([ClipId.sitDown, ClipId.tea]);
          _start(ClipId.batPin);
        } else {
          _queue
            ..clear()
            ..add(ClipId.idle);
          _start(ClipId.batPin);
        }
        return true;
      case ClipId.typing:
        _queue
          ..clear()
          ..add(ClipId.typing);
        _start(ClipId.fishGag);
        return true;
      case ClipId.sleep:
        _queue
          ..clear()
          ..add(ClipId.sleep);
        _start(ClipId.grumpy);
        return true;
      case ClipId.study:
        _queue
          ..clear()
          ..add(ClipId.study);
        _start(ClipId.stuckGag);
        return true;
      case ClipId.vibe:
        _queue
          ..clear()
          ..add(ClipId.vibe);
        _start(ClipId.danceGag);
        return true;
      case ClipId.jam:
        _queue
          ..clear()
          ..add(ClipId.jam);
        _start(ClipId.jamDance);
        return true;
      case ClipId.bath || ClipId.eat || ClipId.potty || ClipId.lounge || ClipId.gaming:
        if (_boop < 1.1) return false;
        _boop = 0; // startled: a hop and a "!" without leaving what it's doing
        return true;
      default:
        return false;
    }
  }

  /// Jump straight into the loop for [m] (app resume, viewer first state).
  void snapTo(CatMode m) {
    _mode = m;
    _queue.clear();
    _clip = _target();
    _clipT = m == CatMode.atHome ? 1.5 : 0; // props already out
    _blendT = 1;
    _blendFrom = null;
    history.add(_clip);
  }

  /// Advance by [dt] seconds and return the pose to draw.
  Pose update(double dt) {
    _time += dt;
    _clipT += dt;
    final spec = clipSpecs[_clip]!;
    if (!spec.loops && _clipT >= spec.duration!) {
      // If the situation changed while this one-shot played, plan afresh.
      if (_queue.isEmpty || _queue.last != _target()) {
        _queue
          ..clear()
          ..addAll(plan(baseOf(_clip), _mode, home: _target()));
      }
      _next();
    } else if (_mode == CatMode.atHome && _queue.isEmpty && spec.loops && (_clipT > homeMinStay || _skipStay)) {
      // A new minute at home: on to the next activity.
      _skipStay = false;
      final want = homeActivityAt(clock());
      if (want != _clip && homeActivities.contains(_clip)) {
        _queue.addAll(plan(_clip, CatMode.atHome, home: want));
        _next();
      }
    }
    final forceRight = _clip == ClipId.typing ||
        _clip == ClipId.hopOnChair ||
        _clip == ClipId.fishGag ||
        _clip == ClipId.leaveOffice && _clipT < 1.3 ||
        baseOf(_clip) == ClipId.sleep ||
        _clip == ClipId.wakeUp && _clipT < 1.8 ||
        baseOf(_clip) == ClipId.study && !(_clip == ClipId.closeBook && _clipT > 1.0) ||
        baseOf(_clip) == ClipId.vibe && !(_clip == ClipId.headphonesOff && _clipT > 0.9) ||
        isHomeLife(_clip) || _clip == ClipId.homeStroll || _clip == ClipId.homeWake ||
        _clip == ClipId.leaveHome && _clipT < 0.5;
    final target = forceRight ? 1.0 : _facingTarget;
    final step = dt / 0.22 * 2;
    _facing += (target - _facing).clamp(-step, step);

    final ctx = ClipCtx(amp: reducedMotion ? 0.35 : 1, cadence: cadence, time: _time);
    var pose = sampleClip(_clip, _clipT, ctx);
    if (_blendFrom != null && _blendT < 1) {
      _blendT = math.min(1, _blendT + dt / _blendDur);
      pose = Pose.lerp(_blendFrom!, pose, easeInOut(_blendT));
    }
    if (_boop < 1.1) {
      _boop += dt;
      final b = _boop;
      final a = reducedMotion ? 0.35 : 1.0;
      pose[P.exclaim] = math.max(pose[P.exclaim], span(b, 0, 0.08) * (1 - span(b, 0.7, 1.0)));
      pose[P.eyeWide] = math.max(pose[P.eyeWide], 1 - span(b, 0.6, 1.0));
      pose[P.eyeOpen] = math.max(pose[P.eyeOpen], 1 - span(b, 0.6, 1.0));
      pose[P.rootY] += -6 * a * math.sin(math.pi * span(b, 0, 0.45));
      pose[P.earFront] += 0.5 * (1 - span(b, 0.5, 1.0));
      pose[P.earBack] += 0.5 * (1 - span(b, 0.5, 1.0));
    }
    pose[P.facing] = _facing;
    pose[P.time] = _time;
    _last = pose;
    return pose;
  }
}
