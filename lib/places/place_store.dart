import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/seed_places.dart';
import '../tracking/place_monitor.dart';

enum PlaceKind { office, home }

extension PlaceKindText on PlaceKind {
  String get label => this == PlaceKind.office ? 'office' : 'home';
  String get title => this == PlaceKind.office ? 'My office' : 'My home';
}

/// App preferences + saved places. Everything stays on this phone.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs);
  final SharedPreferences _prefs;

  static const defaultRadius = 100.0;

  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppStore._(prefs);
    // Public builds (--dart-define=PUBLIC_BUILD=true) never carry anyone's places.
    const publicBuild = bool.fromEnvironment('PUBLIC_BUILD');
    if (!publicBuild && !(prefs.getBool('seeded') ?? false)) {
      if (seedOffice != null) await s.setPlace(PlaceKind.office, Place(center: seedOffice!, radiusM: defaultRadius));
      if (seedHome != null) await s.setPlace(PlaceKind.home, Place(center: seedHome!, radiusM: 60));
      await prefs.setBool('seeded', true);
    }
    return s;
  }

  Place? place(PlaceKind k) {
    final raw = _prefs.getString('place_${k.label}');
    if (raw == null) return null;
    try {
      return Place.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setPlace(PlaceKind k, Place? p) async {
    if (p == null) {
      await _prefs.remove('place_${k.label}');
    } else {
      await _prefs.setString('place_${k.label}', jsonEncode(p.toJson()));
    }
    notifyListeners();
  }

  bool get reducedMotion => _prefs.getBool('reducedMotion') ?? false;
  set reducedMotion(bool v) {
    _prefs.setBool('reducedMotion', v);
    notifyListeners();
  }

  /// 0 small, 1 medium, 2 large.
  int get catSize => _prefs.getInt('catSize') ?? 1;
  set catSize(int v) {
    _prefs.setInt('catSize', v);
    notifyListeners();
  }

  double get catScale => const [0.62, 0.8, 1.0][catSize.clamp(0, 2)];

  bool get explainedLocation => _prefs.getBool('explainedLocation') ?? false;
  set explainedLocation(bool v) => _prefs.setBool('explainedLocation', v);

  /// The live share in progress (id, write token, end time), so it can be
  /// stopped after the app restarts. Never contains positions.
  String? get shareJson => _prefs.getString('share');
  set shareJson(String? v) {
    if (v == null) {
      _prefs.remove('share');
    } else {
      _prefs.setString('share', v);
    }
  }

  /// Picks up what the trip service wrote (prefs are per-isolate caches).
  Future<void> reload() => _prefs.reload();

  /// True while a trip runs (in the Android service, or in-process).
  bool get tripRunning => _prefs.getBool('tripRunning') ?? false;
  Future<void> setTripRunning(bool v) => _prefs.setBool('tripRunning', v);

  /// In-progress trip journal (no coordinates), for interrupted sessions.
  String? get activeTrip => _prefs.getString('activeTrip');
  Future<void> saveActiveTrip(String? json) async {
    if (json == null) {
      await _prefs.remove('activeTrip');
    } else {
      await _prefs.setString('activeTrip', json);
    }
  }
}
