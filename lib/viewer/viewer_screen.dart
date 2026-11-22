import 'dart:async';
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cat/cat_layer.dart';
import '../core/geo.dart';
import '../share/share_state.dart';
import '../ui/theme.dart';
import 'viewer_session.dart';

enum ViewStatus { loading, live, ended, unknown, offline }

class _Projector implements MapProjector {
  MapCamera? camera;
  @override
  Offset? toScreen(GeoPoint p) => camera?.latLngToScreenOffset(LatLng(p.lat, p.lng));
  @override
  double get bearingDeg => 0;
}

/// What someone sees when they open a GoliCat live-share link.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.shareId,
    required this.api,
    this.client,
    this.pollEvery,
    this.showTiles = true,
  });

  /// null = the link has no share id in it.
  final String? shareId;

  /// e.g. https://golicat.example.workers.dev/api/s/
  final Uri api;
  final http.Client? client;
  final Duration? pollEvery;

  /// Tests turn the network tiles off.
  final bool showTiles;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> with SingleTickerProviderStateMixin {
  late final http.Client _client = widget.client ?? http.Client();
  final _session = ViewerSession();
  final _projector = _Projector();
  final _map = MapController();
  bool _mapReady = false;
  bool _follow = true;
  ViewStatus _status = ViewStatus.loading;
  DateTime? _until;
  bool _open = false;
  Timer? _poll, _clockTick;
  int _failures = 0;
  bool _fetching = false;
  GeoPoint? _camTarget;

  late final AnimationController _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  LatLng? _from, _to;
  double _zFrom = 0, _zTo = 0;

  @override
  void initState() {
    super.initState();
    _glide.addListener(() {
      if (_from == null || _to == null || !_mapReady) return;
      final t = Curves.easeInOut.transform(_glide.value);
      _map.move(
        LatLng(
          _from!.latitude + (_to!.latitude - _from!.latitude) * t,
          _from!.longitude + (_to!.longitude - _from!.longitude) * t,
        ),
        _zFrom + (_zTo - _zFrom) * t,
      );
    });
    if (widget.shareId == null) {
      _status = ViewStatus.unknown;
    } else {
      _fetch();
      _poll = Timer.periodic(widget.pollEvery ?? const Duration(seconds: 3), (_) => _fetch());
    }
    _clockTick = Timer.periodic(const Duration(seconds: 1), (_) {
      // A timed share closes on the second, without waiting for the next poll.
      final u = _until;
      if (!_open && u != null && _status == ViewStatus.live && !DateTime.now().add(_session.clockOffset).isBefore(u)) {
        _end(ViewStatus.ended);
      }
      _session.refresh();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clockTick?.cancel();
    _glide.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_fetching) return; // slow network: don't pile requests on top of each other
    _fetching = true;
    try {
      final r = await _client.get(widget.api.resolve(widget.shareId!)).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _failures = 0;
      if (r.statusCode == 410) return _end(ViewStatus.ended);
      if (r.statusCode == 404 || r.statusCode == 400) return _end(ViewStatus.unknown);
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _until = j['until'] is num ? DateTime.fromMillisecondsSinceEpoch((j['until'] as num).toInt()) : null;
      _open = j['open'] == true;
      if (j['now'] is num) {
        _session.clockOffset = Duration(milliseconds: (j['now'] as num).toInt() - DateTime.now().millisecondsSinceEpoch);
      }
      final st = ShareState.fromJson(j['state'] as Map<String, dynamic>?);
      if (st != null && (st.at != _session.state?.at || _session.state == null)) {
        _session.apply(st);
        _followTo(st.point);
      }
      setState(() => _status = ViewStatus.live);
    } catch (_) {
      if (!mounted) return;
      _failures++;
      if (_failures >= 3) setState(() => _status = ViewStatus.offline);
    } finally {
      _fetching = false;
    }
  }

  void _end(ViewStatus s) {
    _poll?.cancel();
    setState(() => _status = s);
  }

  void _followTo(GeoPoint p, {bool force = false}) {
    if (!_mapReady || (!_follow && !force)) return;
    final first = _camTarget == null;
    if (!force && !first && distanceM(_camTarget!, p) < 2) return;
    _camTarget = p;
    final cam = _map.camera;
    _from = cam.center;
    _to = LatLng(p.lat, p.lng);
    _zFrom = cam.zoom;
    _zTo = first || force ? 17.5 : cam.zoom;
    _glide.duration = Duration(milliseconds: first ? 10 : 900);
    _glide.forward(from: 0);
  }

  String _ago(Duration d) {
    if (d.inSeconds < 10) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds} s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ${d.inMinutes % 60} min ago';
  }

  static String _hm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final st = _session.state;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(23.7806, 90.4000),
              initialZoom: 12.5,
              minZoom: 3,
              maxZoom: 19.5,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                _mapReady = true;
                final p = _session.state?.point;
                if (p != null) _followTo(p);
              },
              onPositionChanged: (cam, hasGesture) {
                if (hasGesture && _follow) {
                  _glide.stop();
                  setState(() => _follow = false);
                }
              },
            ),
            children: [
              if (widget.showTiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'bd.golicat.viewer',
                  maxNativeZoom: 19,
                ),
              if (st != null && (_status == ViewStatus.live || _status == ViewStatus.offline))
                Builder(
                  builder: (context) {
                    _projector.camera = MapCamera.of(context);
                    return CatLayer(session: _session, projector: _projector, scale: 0.9);
                  },
                ),
            ],
          ),
          Positioned(
            right: 10,
            bottom: mq.padding.bottom + 8,
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 11, color: Color(0xFF333333)),
                ),
              ),
            ),
          ),
          if (!_follow && st != null && _status == ViewStatus.live)
            Positioned(
              right: 14,
              bottom: mq.padding.bottom + 40,
              child: FloatingActionButton.small(
                tooltip: 'Back to GoliCat',
                onPressed: () {
                  setState(() => _follow = true);
                  _followTo(_session.position.shown ?? st.point, force: true);
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          Positioned(
            top: mq.padding.top + 10,
            left: 10,
            right: 10,
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _card(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = _session.state;
    late final String title;
    late final String detail;
    var dot = GoliTheme.red;
    switch (_status) {
      case ViewStatus.loading:
        title = 'Finding GoliCat…';
        detail = 'Opening the live map.';
        dot = Colors.grey;
      case ViewStatus.ended:
        title = 'Sharing has ended';
        detail = 'GoliCat has stopped sharing its location. The last position was deleted.';
        dot = Colors.grey;
      case ViewStatus.unknown:
        title = 'This link isn\'t live';
        detail = 'It may have expired or been typed wrong. Ask for a new link.';
        dot = Colors.grey;
      case ViewStatus.offline:
        title = 'Can\'t reach GoliCat';
        detail = 'Check your internet. Trying again…';
        dot = Colors.orange;
      case ViewStatus.live:
        if (st == null) {
          title = 'Waiting for the first position…';
          detail = 'The sharer\'s phone hasn\'t found GPS yet.';
          dot = Colors.orange;
        } else {
          final age = _session.age;
          title = _session.stale ? 'Last seen ${_ago(age!)}' : _session.director.label;
          final parts = <String>[
            if (!_session.stale && age != null) 'Updated ${_ago(age)}',
            if (_session.stale) 'Phone may be locked or offline',
            if (st.accuracy > 0) '±${st.accuracy.round()} m',
            if (st.moving && !_session.stale) '${(st.speed * 3.6).toStringAsFixed(0)} km/h',
            if (_open) 'until the trip ends' else if (_until != null) 'until ${_hm(_until!)}',
          ];
          detail = parts.join(' · ');
          if (_session.stale) dot = Colors.orange;
        }
    }
    return Material(
      elevation: 6,
      shadowColor: Colors.black38,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status == ViewStatus.live ? 'GoliCat · LIVE' : 'GoliCat', style: t.labelSmall?.copyWith(letterSpacing: 1.2, color: GoliTheme.red)),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(detail, style: t.bodySmall),
            if (_status == ViewStatus.ended || _status == ViewStatus.unknown)
              TextButton(
                onPressed: () => launchUrl(Uri.base.resolve('/get/'), webOnlyWindowName: '_self'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: const Text('Get GoliCat for Android →'),
              ),
          ],
        ),
      ),
    );
  }
}
