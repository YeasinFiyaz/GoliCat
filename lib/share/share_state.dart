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
  });

  final GeoPoint point;
  final CatMode mode;
  final double accuracy;
  final double headingDeg;
  final double speed;
  final bool moving;

  /// Server receive time (viewer side only).
  final DateTime? at;

  Map<String, dynamic> toJson() => {
        'lat': point.lat,
        'lng': point.lng,
        'acc': double.parse(accuracy.toStringAsFixed(1)),
        'heading': double.parse(headingDeg.toStringAsFixed(1)),
        'speed': double.parse(speed.toStringAsFixed(2)),
        'moving': moving,
        'mode': mode.name,
      };

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
    );
  }
}
