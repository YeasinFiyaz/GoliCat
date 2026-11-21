import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/share_config.dart';
import '../core/geo.dart';
import '../places/place_store.dart';
import '../tracking/activity_engine.dart';
import '../tracking/roam_session.dart';
import 'share_state.dart';

/// Phone side of a live share: a secret link, its own write token, and a
/// position push every few seconds while a trip runs. Stopping deletes it.
class ShareController extends ChangeNotifier {
  ShareController(this.store, {http.Client? client, DateTime Function()? clock, String? baseUrl})
      : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        baseUrl = baseUrl ?? shareBaseUrl {
    _restore();
  }

  final AppStore store;
  final http.Client _client;
  final DateTime Function() _clock;
  final String baseUrl;

  /// "Until the trip ends" still has a server-side limit.
  static const tripLimit = Duration(hours: 12);
  static const movingEvery = Duration(seconds: 5);
  static const stillEvery = Duration(seconds: 15);
  static const retryAfter = Duration(seconds: 10);

  String? id;
  String? _token;
  DateTime? until;
  bool untilTripEnds = false;

  /// True while the last push failed (no internet, server down).
  bool failing = false;
  DateTime? lastSentAt;
  DateTime? _lastTryAt;
  CatMode? _lastMode;
  String? _lastSkin;
  GeoPoint? _lastPoint;
  bool _busy = false;

  bool get active => id != null;
  String? get link => id == null ? null : '$baseUrl/s/$id';
  Uri _api(String id) => Uri.parse('$baseUrl/api/s/$id');

  static String _random(int bytes) {
    final r = math.Random.secure();
    return base64UrlEncode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  void _restore() {
    final raw = store.shareJson;
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      id = j['id'] as String;
      _token = j['token'] as String;
      until = DateTime.fromMillisecondsSinceEpoch(j['until'] as int);
      untilTripEnds = j['untilTripEnds'] == true;
    } catch (_) {
      id = null;
      store.shareJson = null;
    }
  }

  void _persist() {
    store.shareJson = id == null
        ? null
        : jsonEncode({'id': id, 'token': _token, 'until': until!.millisecondsSinceEpoch, 'untilTripEnds': untilTripEnds});
  }

  /// Starts a new share (a brand-new link every time). [duration] null = until
  /// the trip ends. Returns false if the relay couldn't be reached.
  Future<bool> start({Duration? duration, ShareState? now}) async {
    if (active) await stop();
    final newId = _random(16), token = _random(32);
    final end = _clock().add(duration ?? tripLimit);
    try {
      final r = await _client
          .post(_api(newId),
              headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
              body: jsonEncode({'until': end.millisecondsSinceEpoch, ...?now?.toJson(), if (now != null) 'skin': store.catSkinId}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      id = newId;
      _token = token;
      until = DateTime.fromMillisecondsSinceEpoch((j['until'] as num).toInt());
      untilTripEnds = duration == null;
      failing = false;
      lastSentAt = _lastTryAt = _clock();
      _lastMode = now?.mode;
      _lastPoint = now?.point;
      _lastSkin = store.catSkinId;
      _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ends the share: the link stops working and the server forgets the position.
  Future<void> stop() async {
    final oldId = id, oldToken = _token;
    id = null;
    _token = null;
    until = null;
    failing = false;
    _lastTryAt = null;
    _persist();
    notifyListeners();
    if (oldId == null) return;
    try {
      await _client
          .delete(_api(oldId), headers: {'authorization': 'Bearer $oldToken'})
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Unreachable now: the share still expires on the server by itself.
    }
  }

  static ShareState? stateOf(RoamSession s) {
    final snap = s.snap;
    final p = snap?.position;
    if (snap == null || p == null) return null;
    return ShareState(
      point: p,
      mode: snap.mode,
      accuracy: snap.motion.lastAccuracy,
      headingDeg: snap.motion.headingDeg,
      speed: snap.motion.speed,
      moving: snap.motion.moving,
    );
  }

  /// Called every second by the trip. Pushes when due: every 5 s while moving,
  /// every 15 s while still, and quickly when the cat's mode changes.
  Future<void> tick(RoamSession session) async {
    if (!active || _busy) return;
    final now = _clock();
    if (until != null && now.isAfter(until!)) {
      await stop();
      return;
    }
    final st = stateOf(session);
    final skin = store.catSkinId;
    final changed = st != null &&
        (st.mode != _lastMode || skin != _lastSkin || (_lastPoint != null && distanceM(_lastPoint!, st.point) > 25));
    final every = failing ? retryAfter : (st?.moving ?? false) ? movingEvery : stillEvery;
    final sinceTry = _lastTryAt == null ? null : now.difference(_lastTryAt!);
    final due = sinceTry == null || sinceTry >= every;
    final quick = changed && !failing && (sinceTry == null || sinceTry >= const Duration(seconds: 2));
    if (!due && !quick) return;
    _busy = true;
    _lastTryAt = now;
    final shareId = id!;
    try {
      final r = await _client
          .post(_api(shareId),
              headers: {'content-type': 'application/json', 'authorization': 'Bearer $_token'},
              body: jsonEncode({...?st?.toJson(), if (st != null) 'skin': skin}))
          .timeout(const Duration(seconds: 10));
      if (id != shareId) return; // stopped meanwhile
      if (r.statusCode == 410 || r.statusCode == 403) {
        // Expired or ended on the server.
        id = null;
        _token = null;
        _persist();
      } else if (r.statusCode == 200) {
        lastSentAt = now;
        failing = false;
        _lastMode = st?.mode ?? _lastMode;
        if (st != null) _lastSkin = skin;
        _lastPoint = st?.point ?? _lastPoint;
      } else if (r.statusCode == 429) {
        failing = false; // too soon: the server kept the old state, so try again next tick
      } else {
        failing = true;
      }
    } catch (_) {
      if (id == shareId) failing = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
