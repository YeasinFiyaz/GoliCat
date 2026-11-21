import 'dart:math' as math;

/// A plain latitude/longitude pair. The engines use this instead of the
/// Google Maps type so they can be tested without any plugin.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, double> toJson() => {'lat': lat, 'lng': lng};
  static GeoPoint fromJson(Map<String, dynamic> j) =>
      GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
  @override
  String toString() =>
      'GeoPoint(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

const double _earthRadius = 6371008.8;
double _rad(double d) => d * math.pi / 180.0;
double _deg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in metres.
double distanceM(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(s)));
}

/// Initial bearing from [a] to [b], degrees clockwise from north (0..360).
double bearingDeg(GeoPoint a, GeoPoint b) {
  final la1 = _rad(a.lat), la2 = _rad(b.lat);
  final dLng = _rad(b.lng - a.lng);
  final y = math.sin(dLng) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) -
      math.sin(la1) * math.cos(la2) * math.cos(dLng);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Moves [p] by [east] / [north] metres (small offsets only).
GeoPoint offsetM(GeoPoint p, double east, double north) {
  final dLat = north / _earthRadius;
  final dLng = east / (_earthRadius * math.cos(_rad(p.lat)));
  return GeoPoint(p.lat + _deg(dLat), p.lng + _deg(dLng));
}

/// Local east/north metres of [p] relative to [origin] (small areas only).
({double east, double north}) toLocalM(GeoPoint origin, GeoPoint p) {
  final north = _rad(p.lat - origin.lat) * _earthRadius;
  final east = _rad(p.lng - origin.lng) * _earthRadius * math.cos(_rad(origin.lat));
  return (east: east, north: north);
}

GeoPoint lerpGeo(GeoPoint a, GeoPoint b, double t) =>
    GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);

/// Web-Mercator world coordinates in "zoom-0 pixels" (0..256).
({double x, double y}) mercatorWorld(GeoPoint p) {
  final siny = math.sin(_rad(p.lat)).clamp(-0.9999, 0.9999);
  return (
    x: 256 * (0.5 + p.lng / 360),
    y: 256 * (0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi)),
  );
}
