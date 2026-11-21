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
  CatDirector({this.reducedMotion = false});

  bool reducedMotion;

  CatMode _mode = CatMode.starting;
  ClipId _clip = ClipId.idle;
  double _clipT = 0;
  final List<ClipId> _queue = [];
  double _time = 0;

  Pose? _blendFrom;
  double _blendT = 1;
  static const _blendDur = 0.22;

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
      };

  /// The transition plan from the current base loop into [target]'s loop.
  static List<ClipId> plan(ClipId fromBase, CatMode target) {
    final to = loopFor(target);
    if (fromBase == to) return [to];
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
        out.add(ClipId.wakeUp);
      case ClipId.study:
        out.add(ClipId.closeBook);
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
        out.add(ClipId.tuckIn);
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
      ..addAll(plan(baseOf(_clip), _mode));
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
      default:
        return false;
    }
  }

  /// Jump straight into the loop for [m] (app resume, viewer first state).
  void snapTo(CatMode m) {
    _mode = m;
    _queue.clear();
    _clip = loopFor(m);
    _clipT = 0;
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
      if (_queue.isEmpty || _queue.last != loopFor(_mode)) {
        _queue
          ..clear()
          ..addAll(plan(baseOf(_clip), _mode));
      }
      _next();
    }
    final forceRight = _clip == ClipId.typing ||
        _clip == ClipId.hopOnChair ||
        _clip == ClipId.fishGag ||
        _clip == ClipId.leaveOffice && _clipT < 1.3 ||
        baseOf(_clip) == ClipId.sleep ||
        _clip == ClipId.wakeUp && _clipT < 1.8 ||
        baseOf(_clip) == ClipId.study && !(_clip == ClipId.closeBook && _clipT > 1.0) ||
        baseOf(_clip) == ClipId.vibe && !(_clip == ClipId.headphonesOff && _clipT > 0.9);
    final target = forceRight ? 1.0 : _facingTarget;
    final step = dt / 0.22 * 2;
    _facing += (target - _facing).clamp(-step, step);

    final ctx = ClipCtx(amp: reducedMotion ? 0.35 : 1, cadence: cadence, time: _time);
    var pose = sampleClip(_clip, _clipT, ctx);
    if (_blendFrom != null && _blendT < 1) {
      _blendT = math.min(1, _blendT + dt / _blendDur);
      pose = Pose.lerp(_blendFrom!, pose, easeInOut(_blendT));
    }
    pose[P.facing] = _facing;
    pose[P.time] = _time;
    _last = pose;
    return pose;
  }
}
