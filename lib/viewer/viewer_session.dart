import '../cat/cat_director.dart';
import '../cat/cat_skin.dart';
import '../cat/cat_source.dart';
import '../core/position_glide.dart';
import '../share/share_state.dart';
import '../tracking/activity_engine.dart';

/// Drives the same cat as the app, from a live share's latest state.
class ViewerSession implements CatSource {
  ViewerSession({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Server time minus this device's time, so a wrong phone clock can't make
  /// a live share look stale.
  Duration clockOffset = Duration.zero;
  DateTime _now() => _clock().add(clockOffset);

  /// No update for this long = the phone went quiet (paper map comes out).
  static const staleAfter = Duration(seconds: 75);

  @override
  final director = CatDirector();
  @override
  final position = PositionGlide();

  ShareState? state;
  bool _first = true;

  @override
  bool get moving => !stale && (state?.moving ?? false);
  @override
  double get headingDeg => state?.headingDeg ?? 0;

  Duration? get age {
    final at = state?.at;
    if (at == null) return null;
    final d = _now().difference(at);
    return d.isNegative ? Duration.zero : d;
  }
  bool get stale => age != null && age! > staleAfter;

  void apply(ShareState s) {
    state = s;
    // Show the avatar the sharer picked (older apps send none: original cat).
    activeCatSkin.value = CatSkin.byId(s.skin);
    final mode = stale ? CatMode.lost : s.mode;
    if (_first) {
      director.snapTo(mode);
      _first = false;
    } else {
      director.setMode(mode);
    }
    director.cadence = s.mode == CatMode.fast ? (s.speed / 6).clamp(0.8, 1.4) : (s.speed / 1.4).clamp(0.75, 1.6);
    position.target(s.point, _now());
  }

  /// Called between polls so a silent phone turns into "lost".
  void refresh() {
    final s = state;
    if (s == null) return;
    director.setMode(stale ? CatMode.lost : s.mode);
  }
}
