import '../core/geo.dart';

/// One location reading from the phone (or from a test script).
class LocationFix {
  const LocationFix({
    required this.point,
    required this.time,
    required this.accuracy,
    this.speed = -1,
    this.speedAccuracy = -1,
    this.heading = -1,
  });

  final GeoPoint point;
  final DateTime time;

  /// Horizontal accuracy radius in metres (68% confidence).
  final double accuracy;

  /// Reported speed in m/s, or negative when unknown.
  final double speed;
  final double speedAccuracy;

  /// Reported course in degrees, or negative when unknown.
  final double heading;
}
