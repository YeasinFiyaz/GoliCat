import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cat/cat_skin.dart';
import '../config/app_build.dart';
import '../config/seed_places.dart';
import 'custom_place.dart';
import '../tracking/place_monitor.dart';

/// The kinds of place the cat reacts to. Adding one: a line here, a monitor
/// in ActivityEngine, a CatMode + clips, and an entry in the map's pin table.
enum PlaceKind { office, home, education, hangout }

extension PlaceKindText on PlaceKind {
  /// Preferences key and status-map key; never rename once released.
  String get label => name;

  String get title => switch (this) {
        PlaceKind.office => 'My office',
        PlaceKind.home => 'My home',
        PlaceKind.education => 'My school / university',
        PlaceKind.hangout => 'My hangout spot',
      };

  /// What the cat does there, for menus and the place editor.
  String get blurb => switch (this) {
        PlaceKind.office => 'GoliCat clocks in here',
        PlaceKind.home => 'GoliCat naps under its kantha here',
        PlaceKind.education => 'GoliCat puts on its glasses and does homework',
        PlaceKind.hangout => 'GoliCat puts on headphones and vibes',
      };

  String get arrivalText => switch (this) {
        PlaceKind.office => 'GoliCat clocks in',
        PlaceKind.home => 'GoliCat goes to sleep',
        PlaceKind.education => 'GoliCat sits down to study',
        PlaceKind.hangout => 'GoliCat puts its headphones on',
      };

  double get defaultRadius => switch (this) {
        PlaceKind.office => AppStore.defaultRadius,
        PlaceKind.home => 60,
        PlaceKind.education => 120,
        PlaceKind.hangout => 60,
      };
}

/// App preferences + saved places. Everything stays on this phone.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs);
  final SharedPreferences _prefs;

  static const defaultRadius = 100.0;

  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppStore._(prefs);
    // Anything saved before this start? (Checked before the seed below adds some.)
    final hadData = prefs.getKeys().any((k) => k.startsWith('place_') || k == 'catSkin' || k == 'customPlaces');
    activeCatSkin.value = CatSkin.byId(prefs.getString('catSkin'));
    // Public builds (--dart-define=PUBLIC_BUILD=true) never carry anyone's places.
    const publicBuild = bool.fromEnvironment('PUBLIC_BUILD');
    if (!publicBuild && !(prefs.getBool('seeded') ?? false)) {
      if (seedOffice != null) await s.setPlace(PlaceKind.office, Place(center: seedOffice!, radiusM: defaultRadius));
      if (seedHome != null) await s.setPlace(PlaceKind.home, Place(center: seedHome!, radiusM: 60));
      await prefs.setBool('seeded', true);
    }
    await s._upgrade(hadData);
    return s;
  }

  // ---- updates ---------------------------------------------------------------

  /// Layout of the saved data. Raise it with a step in [_upgrade] whenever a
  /// release changes what is stored, so an update converts old data in place
  /// and nobody has to uninstall or set things up again.
  static const dataVersion = 2;

  /// The build this phone ran before the current one, when this start is the
  /// first one after an update (null otherwise).
  int? updatedFrom;

  Future<void> _upgrade(bool hadData) async {
    final had = _prefs.getInt('dataVersion') ?? 1;
    if (had < 2) {
      // 1.0.4: custom places arrive under their own key. Nothing older needs
      // converting, and nothing saved is ever deleted by an update: anything
      // unreadable is simply skipped when read.
    }
    if (had != dataVersion) await _prefs.setInt('dataVersion', dataVersion);
    final lastBuild = _prefs.getInt('lastBuild');
    if (lastBuild != null && lastBuild < appBuild) updatedFrom = lastBuild;
    if (lastBuild == null && had == 1 && hadData) {
      updatedFrom = 0; // came from a build older than this tracking
    }
    if (lastBuild != appBuild) await _prefs.setInt('lastBuild', appBuild);
  }

  // ---- custom places -----------------------------------------------------------

  /// Parsed once and kept: the map asks for these on every rebuild.
  List<CustomPlace>? _customCache;

  List<CustomPlace> get customPlaces => _customCache ??= List.unmodifiable(_readCustom());

  List<CustomPlace> _readCustom() {
    final raw = _prefs.getString('customPlaces');
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final j in list) ?CustomPlace.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCustom(List<CustomPlace> list) async {
    await _prefs.setString('customPlaces', jsonEncode([for (final c in list) c.toJson()]));
    _customCache = null;
    notifyListeners();
  }

  /// Adds or replaces (same id) a custom place.
  Future<void> saveCustomPlace(CustomPlace p) async {
    final list = [...customPlaces];
    final i = list.indexWhere((c) => c.id == p.id);
    if (i >= 0) {
      list[i] = p;
    } else {
      list.add(p);
    }
    await _saveCustom(list);
  }

  Future<void> removeCustomPlace(String id) => _saveCustom([...customPlaces]..removeWhere((c) => c.id == id));


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

  /// The chosen avatar. Setting it changes every cat drawn in the app.
  String get catSkinId => CatSkin.byId(_prefs.getString('catSkin')).id;
  set catSkinId(String id) {
    final skin = CatSkin.byId(id);
    _prefs.setString('catSkin', skin.id);
    activeCatSkin.value = skin;
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
  Future<void> reload() async {
    await _prefs.reload();
    _customCache = null;
    activeCatSkin.value = CatSkin.byId(_prefs.getString('catSkin'));
  }

  /// True while a trip runs (in the Android service, or in-process).
  bool get tripRunning => _prefs.getBool('tripRunning') ?? false;
  Future<void> setTripRunning(bool v) => _prefs.setBool('tripRunning', v);

  /// When the running trip last proved it was alive (written once a minute),
  /// so a trip stopped by an app update can be told from one that died long ago.
  DateTime? get tripAliveAt {
    final ms = _prefs.getInt('tripAliveAt');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markTripAlive(DateTime at) => _prefs.setInt('tripAliveAt', at.millisecondsSinceEpoch);

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
