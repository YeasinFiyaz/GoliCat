import '../core/geo.dart';
import '../tracking/activity_engine.dart';

/// The one thing a live share sends: where the cat is and what it's doing.
/// No history, no trip journal, no saved places.
class ShareState {
  const ShareState({
    required this.point,
    required this.mode,
    this.accuracy = 0,
    this.headingDeg = 0,
    this.speed = 0,
    this.moving = false,
    this.at,
    this.skin,
  });

  final GeoPoint point;
  final CatMode mode;
  final double accuracy;
  final double headingDeg;
  final double speed;
  final bool moving;

  /// Server receive time (viewer side only).
  final DateTime? at;

  /// Avatar id, so the person watching sees the same cat (viewer side only).
  final String? skin;

  Map<String, dynamic> toJson() => {
        'lat': point.lat,
        'lng': point.lng,
        'acc': double.parse(_finite(accuracy).toStringAsFixed(1)),
        'heading': double.parse(_finite(headingDeg).toStringAsFixed(1)),
        'speed': double.parse(_finite(speed).toStringAsFixed(2)),
        'moving': moving,
        'mode': mode.name,
      };

  /// JSON has no NaN/Infinity; a bad reading must not break every push.
  static double _finite(double v) => v.isFinite ? v : 0;

  static ShareState? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    final mode = CatMode.values.where((m) => m.name == j['mode']).firstOrNull ?? CatMode.idle;
    final ts = j['ts'];
    return ShareState(
      point: GeoPoint(lat.toDouble(), lng.toDouble()),
      mode: mode,
      accuracy: (j['acc'] as num?)?.toDouble() ?? 0,
      headingDeg: (j['heading'] as num?)?.toDouble() ?? 0,
      speed: (j['speed'] as num?)?.toDouble() ?? 0,
      moving: j['moving'] == true,
      at: ts is num ? DateTime.fromMillisecondsSinceEpoch(ts.toInt()) : null,
      skin: j['skin'] is String ? j['skin'] as String : null,
    );
  }
}
