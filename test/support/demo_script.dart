import 'dart:math' as math;

import 'package:golicat/core/geo.dart';
import 'package:golicat/tracking/fix.dart';
import 'package:golicat/tracking/place_monitor.dart';

/// A scripted outing on a made-up street grid near 0°N 0°E, used by the
/// engine tests: walk, cha break, fast ride, office, hangout, study, home.
class DemoScript {
  DemoScript() {
    _generate();
  }

  static const origin = GeoPoint(0, 0);
  static final epoch = DateTime(2026, 1, 1, 8, 30);

  static final office = Place(center: offsetM(origin, 520, 42), radiusM: 100);
  static final home = Place(center: offsetM(origin, 850, -150), radiusM: 60);
  static final hangout = Place(center: offsetM(origin, 760, -95), radiusM: 60);
  static final education = Place(center: offsetM(origin, 900, 70), radiusM: 110);
  static const officeLocal = Offset2(520, 42);
  static const homeLocal = Offset2(850, -150);
  static const hangoutLocal = Offset2(760, -95);
  static const educationLocal = Offset2(900, 70);
  static const chaLocal = Offset2(100, 0);

  /// Path keyframes: [seconds, east m, north m].
  static const path = <List<double>>[
    [0, 0, 0], [70, 100, 0], [200, 100, 0], // walk, then cha stall
    [260, 184, 0], [300, 424, 0], // walk, then a fast ride
    [312, 468, 0], [470, 689, 0], // slow down, walk PAST the office
    [520, 619, 0], // signal lost while turning back
    [575, 542, 0], [604, 540, 42], // into the office
    [900, 540, 42], // at work (indoor GPS drift)
    [928, 540, 0], [1010, 668, 0], [1030, 700, 0], // leave
    [1075, 760, -95], [1300, 760, -95], // hangout spot: headphones on
    [1330, 760, 0], [1400, 900, 70], [1650, 900, 70], // university: homework
    [1690, 850, 0], [1740, 850, -150], // walk home
    [1950, 850, -150], // home
  ];

  static const duration = 1950.0;

  final List<LocationFix> fixes = [];

  static Offset2 localAt(double t) {
    for (var i = 1; i < path.length; i++) {
      if (t <= path[i][0]) {
        final a = path[i - 1], b = path[i];
        final u = (t - a[0]) / (b[0] - a[0]);
        return Offset2(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u);
      }
    }
    return Offset2(path.last[1], path.last[2]);
  }

  static double speedAt(double t) {
    final a = localAt(t - 0.5), b = localAt(t + 0.5);
    return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
  }

  void _generate() {
    final r = math.Random(7);
    double gauss() => math.sqrt(-2 * math.log(r.nextDouble() + 1e-9)) * math.cos(2 * math.pi * r.nextDouble());
    for (var s = 0; s <= duration; s++) {
      final t = s.toDouble();
      if (t > 470 && t < 495) continue; // no signal at all
      final p = localAt(t);
      var sigma = 2.5, acc = 6 + r.nextDouble() * 4;
      var speed = speedAt(t) + gauss() * 0.25;
      var spAcc = 0.5;
      if (t >= 495 && t < 520) {
        sigma = 60;
        acc = 90 + r.nextDouble() * 60;
      } else if (t >= 604 && t <= 900) {
        sigma = 9;
        acc = 18 + r.nextDouble() * 24;
        speed = (gauss() * 0.6).abs();
        spAcc = 2.5;
      } else if (t >= 1075 && t <= 1300 || t >= 1400 && t <= 1650) {
        sigma = 6;
        acc = 12 + r.nextDouble() * 14;
        speed = (gauss() * 0.3).abs();
        spAcc = 2.0;
      } else if (t >= 70 && t <= 200 || t >= 1740) {
        sigma = 3.5;
        acc = 8 + r.nextDouble() * 6;
        speed = (gauss() * 0.15).abs();
      }
      var e = p.x + gauss() * sigma, n = p.y + gauss() * sigma;
      // One wild but "accurate-looking" jump during tea, and indoor outliers.
      if (s == 150) {
        n += 45;
        acc = 18;
      }
      if (t > 604 && t < 900 && s % 37 == 0) {
        e += 95;
        acc = 38;
      }
      fixes.add(LocationFix(
        point: offsetM(origin, e, n),
        time: epoch.add(Duration(seconds: s)),
        accuracy: acc,
        speed: math.max(0, speed),
        speedAccuracy: spAcc,
      ));
    }
  }
}

class Offset2 {
  const Offset2(this.x, this.y);
  final double x, y;
}
