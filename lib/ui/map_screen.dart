import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cat/cat_layer.dart';
import '../core/geo.dart';
import '../places/place_store.dart';
import '../tracking/activity_engine.dart';
import '../tracking/location_service.dart';
import '../tracking/place_monitor.dart';
import '../tracking/trip_recorder.dart';
import '../tracking/trip_runner.dart';
import 'comic_screen.dart';
import 'demo_screen.dart';
import 'theme.dart';
import 'trip_controller.dart';

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);
GeoPoint _gp(LatLng p) => GeoPoint(p.latitude, p.longitude);

/// Projects through flutter_map's live camera, so the cat moves exactly with the map.
class OsmProjector implements MapProjector {
  MapCamera? camera;
  @override
  Offset? toScreen(GeoPoint p) => camera?.latLngToScreenOffset(_ll(p));
  @override
  double get bearingDeg => 0; // rotation is disabled: north stays up
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _PlaceDraft {
  _PlaceDraft(this.kind, this.center, this.radius, {required this.existing});
  final PlaceKind kind;
  GeoPoint center;
  double radius;
  final bool existing;
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  late final TripController trip = TripController(widget.store);
  final projector = OsmProjector();
  final _map = MapController();
  bool _mapReady = false;
  bool _follow = true;
  _PlaceDraft? _draft;
  GeoPoint? _lastCameraTarget;
  double _panelHeight = 150;
  final _panelKey = GlobalKey();

  // Smooth camera glide (flutter_map moves instantly by itself).
  late final AnimationController _glide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  LatLng? _glideFrom, _glideTo;
  double _glideZoomFrom = 0, _glideZoomTo = 0;

  static const _dhaka = LatLng(23.7806, 90.4000);

  @override
  void initState() {
    super.initState();
    trip.addListener(_onTrip);
    _glide.addListener(() {
      if (_glideFrom == null || _glideTo == null || !_mapReady) return;
      final t = Curves.easeInOut.transform(_glide.value);
      final lat = _glideFrom!.latitude + (_glideTo!.latitude - _glideFrom!.latitude) * t;
      final lng = _glideFrom!.longitude + (_glideTo!.longitude - _glideFrom!.longitude) * t;
      _map.move(LatLng(lat, lng), _glideZoomFrom + (_glideZoomTo - _glideZoomFrom) * t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  @override
  void dispose() {
    trip.removeListener(_onTrip);
    trip.dispose();
    _glide.dispose();
    super.dispose();
  }

  void _glideTo_(GeoPoint p, {double? zoom, int ms = 900}) {
    if (!_mapReady) return;
    final cam = _map.camera;
    _glideFrom = cam.center;
    _glideTo = _ll(p);
    _glideZoomFrom = cam.zoom;
    _glideZoomTo = zoom ?? cam.zoom;
    _glide.duration = Duration(milliseconds: ms);
    _glide.forward(from: 0);
  }

  Future<void> _attach() async {
    await trip.attach();
    final log = await trip.interruptedTrip();
    if (log == null || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your last trip was interrupted'),
        content: Text(
            'GoliCat stopped while roaming (started ${_hm(log.startedAt)}). The phone may have closed the app. '
            'You can still get its comic, or let it go.'),
        actions: [
          TextButton(
            onPressed: () {
              widget.store.saveActiveTrip(null);
              Navigator.pop(ctx);
            },
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () {
              widget.store.saveActiveTrip(null);
              Navigator.pop(ctx);
              log.endedAt = log.startedAt.add(
                  log.moments.isEmpty ? Duration.zero : log.moments.last.offset + const Duration(minutes: 1));
              _openComic(log);
            },
            child: const Text('Make its comic'),
          ),
        ],
      ),
    );
  }

  void _onTrip() {
    final p = trip.position;
    if (p != null && _follow && trip.active && _draft == null) {
      if (_lastCameraTarget == null || distanceM(_lastCameraTarget!, p) > 2) {
        final first = _lastCameraTarget == null;
        _lastCameraTarget = p;
        _glideTo_(p, zoom: first ? 17.5 : null, ms: first ? 900 : 1000);
      }
    }
    if (mounted) setState(() {});
  }

  // ---- actions -------------------------------------------------------------

  Future<void> _startRoaming() async {
    if (!widget.store.explainedLocation) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => const _WhyLocationSheet(),
      );
      if (ok != true) return;
      widget.store.explainedLocation = true;
    }
    final p = await trip.start();
    if (!mounted) return;
    _follow = true;
    _lastCameraTarget = null;
    switch (p) {
      case LocationProblem.serviceOff:
        _problemDialog('Location is turned off', 'Turn on your phone\'s location so GoliCat can find your street.',
            'Open location settings', trip.permissions.openLocationSettings);
      case LocationProblem.denied:
        _snack('GoliCat needs location permission to walk with you. Tap Start roaming to ask again.');
      case LocationProblem.deniedForever:
        _problemDialog(
            'Location permission is off',
            'You turned off location for GoliCat. Allow "While using the app" in settings to start roaming.',
            'Open app settings',
            trip.permissions.openAppSettings);
      default:
        break;
    }
  }

  Future<void> _endTrip() async {
    final log = await trip.end();
    if (log != null && mounted) _openComic(log);
  }

  void _openComic(TripLog log) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComicScreen(log: log)));
  }

  void _recenter() {
    final p = trip.mirror.position.shown ?? trip.position;
    setState(() => _follow = true);
    if (p != null) {
      _lastCameraTarget = p;
      _glideTo_(p, zoom: 17.5);
    }
  }

  void _onLongPress(TapPosition _, LatLng at) async {
    if (_draft != null) {
      setState(() => _draft!.center = _gp(at));
      return;
    }
    final kind = await showModalBottomSheet<PlaceKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.business_center_outlined),
            title: const Text('Set as my office'),
            subtitle: const Text('GoliCat clocks in here'),
            onTap: () => Navigator.pop(ctx, PlaceKind.office),
          ),
          ListTile(
            leading: const Icon(Icons.bed_outlined),
            title: const Text('Set as my home'),
            subtitle: const Text('GoliCat naps under its kantha here'),
            onTap: () => Navigator.pop(ctx, PlaceKind.home),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (kind == null) return;
    _editPlace(kind, at: _gp(at));
  }

  void _onTap(TapPosition _, LatLng at) {
    if (_draft != null) setState(() => _draft!.center = _gp(at));
  }

  void _editPlace(PlaceKind kind, {GeoPoint? at}) {
    final existing = widget.store.place(kind);
    final center = at ?? existing?.center ?? trip.position;
    if (center == null) {
      _snack('Long-press the map where your ${kind.label} is, or start roaming and use your current location.');
      return;
    }
    setState(() {
      _follow = false;
      _draft = _PlaceDraft(kind, center, existing?.radiusM ?? (kind == PlaceKind.office ? AppStore.defaultRadius : 60),
          existing: existing != null);
    });
    _glideTo_(center, zoom: 16.5);
  }

  Future<void> _saveDraft() async {
    final d = _draft!;
    await widget.store.setPlace(d.kind, Place(center: d.center, radiusM: d.radius));
    trip.placeChanged(d.kind);
    setState(() => _draft = null);
    _snack(d.kind == PlaceKind.office ? 'Office saved on this phone.' : 'Home saved on this phone.');
  }

  Future<void> _removeDraft() async {
    final d = _draft!;
    await widget.store.setPlace(d.kind, null);
    trip.placeChanged(d.kind);
    setState(() => _draft = null);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _problemDialog(String title, String body, String action, Future<void> Function() go) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                go();
              },
              child: Text(action)),
        ],
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        store: widget.store,
        trip: trip,
        onEditHome: () {
          Navigator.pop(ctx);
          _editPlace(PlaceKind.home);
        },
        onDemo: () {
          Navigator.pop(ctx);
          _openDemo();
        },
      ),
    );
  }

  void _openShare() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ShareSheet(trip: trip),
    );
  }

  void _openDemo() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DemoScreen(store: widget.store)));
  }

  // ---- map layers ------------------------------------------------------------

  ({GeoPoint c, double r, bool editing})? _placeView(PlaceKind k) {
    final d = _draft;
    if (d != null && d.kind == k) return (c: d.center, r: d.radius, editing: true);
    final p = widget.store.place(k);
    return p == null ? null : (c: p.center, r: p.radiusM, editing: false);
  }

  List<CircleMarker> _circles() {
    final out = <CircleMarker>[];
    for (final k in PlaceKind.values) {
      final v = _placeView(k);
      if (v == null) continue;
      final col = k == PlaceKind.office ? GoliTheme.red : const Color(0xFF2F5D8A);
      out.add(CircleMarker(
        point: _ll(v.c),
        radius: v.r,
        useRadiusInMeter: true,
        color: col.withValues(alpha: v.editing ? 0.16 : 0.07),
        borderColor: col.withValues(alpha: v.editing ? 0.9 : 0.45),
        borderStrokeWidth: v.editing ? 3 : 2,
      ));
      if (v.editing) {
        out.add(CircleMarker(
          point: _ll(v.c),
          radius: Place(center: v.c, radiusM: v.r).exitRadiusM,
          useRadiusInMeter: true,
          color: Colors.transparent,
          borderColor: col.withValues(alpha: 0.35),
          borderStrokeWidth: 1,
        ));
      }
    }
    return out;
  }

  List<Marker> _markers() {
    final out = <Marker>[];
    for (final k in PlaceKind.values) {
      final v = _placeView(k);
      if (v == null) continue;
      final office = k == PlaceKind.office;
      out.add(Marker(
        point: _ll(v.c),
        width: 40,
        height: 48,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: v.editing ? null : () => _editPlace(k),
          child: _PlacePin(
            icon: office ? Icons.business_center : Icons.bed,
            color: office ? GoliTheme.red : const Color(0xFF2F5D8A),
            big: v.editing,
          ),
        ),
      ));
    }
    return out;
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _panelKey.currentContext?.size?.height;
      if (h != null && (h - _panelHeight).abs() > 1 && mounted) setState(() => _panelHeight = h);
    });

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _dhaka,
            initialZoom: 13.5,
            minZoom: 3,
            maxZoom: 19.5,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () => _mapReady = true,
            onLongPress: _onLongPress,
            onTap: _onTap,
            onPositionChanged: (cam, hasGesture) {
              if (hasGesture && _follow) {
                _glide.stop();
                setState(() => _follow = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'bd.golicat.golicat',
              maxNativeZoom: 19,
            ),
            CircleLayer(circles: _circles()),
            MarkerLayer(markers: _markers()),
            if (trip.active && trip.position != null)
              Builder(builder: (context) {
                projector.camera = MapCamera.of(context);
                return CatLayer(
                  session: trip.mirror,
                  projector: projector,
                  scale: widget.store.catScale,
                  reducedMotion: widget.store.reducedMotion,
                );
              }),
          ],
        ),
        Positioned(
          top: mq.padding.top + 8,
          left: 12,
          right: 12,
          child: _Banners(trip: trip, onShare: _openShare),
        ),
        // OpenStreetMap attribution, always visible above the panel.
        Positioned(
          right: 10,
          bottom: mq.padding.bottom + _panelHeight + 14,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'),
                mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
              child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 11, color: Color(0xFF333333))),
            ),
          ),
        ),
        if (trip.active && !_follow && _draft == null)
          Positioned(
            right: 14,
            bottom: mq.padding.bottom + _panelHeight + 40,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: 'Back to GoliCat',
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            ),
          ),
        Positioned(
          left: 10,
          right: 10,
          bottom: mq.padding.bottom + 10,
          child: KeyedSubtree(
            key: _panelKey,
            child: _draft != null
                ? _PlaceEditor(
                    draft: _draft!,
                    canUseCurrent: trip.position != null,
                    onUseCurrent: () {
                      final p = trip.position;
                      if (p == null) return;
                      setState(() => _draft!.center = p);
                      _glideTo_(p);
                    },
                    onRadius: (r) => setState(() => _draft!.radius = r),
                    onSave: _saveDraft,
                    onCancel: () => setState(() => _draft = null),
                    onRemove: _draft!.existing ? _removeDraft : null,
                  )
                : _StatusPanel(
                    trip: trip,
                    onStart: _startRoaming,
                    onEnd: _endTrip,
                    onOffice: () => _editPlace(PlaceKind.office),
                    onMore: _openSettings,
                    onDemo: _openDemo,
                    onShare: _openShare,
                  ),
          ),
        ),
      ]),
    );
  }
}

class _PlacePin extends StatelessWidget {
  const _PlacePin({required this.icon, required this.color, required this.big});
  final IconData icon;
  final Color color;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final s = big ? 1.15 : 1.0;
    return Transform.scale(
      scale: s,
      alignment: Alignment.bottomCenter,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        Container(width: 3, height: 12, color: color),
      ]),
    );
  }
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String ago(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ${d.inMinutes % 60} min ago';
}

// ---------------------------------------------------------------------------

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.trip,
    required this.onStart,
    required this.onEnd,
    required this.onOffice,
    required this.onMore,
    required this.onDemo,
    required this.onShare,
  });
  final TripController trip;
  final VoidCallback onStart, onEnd, onOffice, onMore, onDemo, onShare;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!trip.active) {
      return _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('GoliCat · গলির বিড়াল', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('A Dhaka street cat that walks your streets with you.', style: t.bodySmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: trip.state == TripState.starting ? null : onStart,
                icon: const Icon(Icons.pets),
                label: Text(trip.state == TripState.starting ? 'Finding you…' : 'Start roaming'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(onPressed: onMore, tooltip: 'Places & settings', icon: const Icon(Icons.tune)),
          ]),
          TextButton(onPressed: onDemo, child: const Text('Try the demo (no location needed)')),
        ]),
      );
    }
    final st = trip.status;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const _LiveDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(st == null || !st.hasFix ? 'Finding you…' : st.label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 2),
        Text(_detail(st), style: t.bodySmall, maxLines: 2),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onEnd,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('End trip'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onOffice,
            icon: const Icon(Icons.business_center_outlined, size: 18),
            label: const Text('Office'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
          ),
          const SizedBox(width: 6),
          trip.shareActive
              ? IconButton.filled(
                  onPressed: onShare,
                  tooltip: 'Sharing live',
                  icon: const Icon(Icons.share_location),
                )
              : IconButton.outlined(
                  onPressed: onShare,
                  tooltip: 'Share live location',
                  icon: const Icon(Icons.share_location_outlined),
                ),
          IconButton(onPressed: onMore, tooltip: 'More', icon: const Icon(Icons.more_vert)),
        ]),
      ]),
    );
  }

  static String _detail(TripStatus? s) {
    if (s == null || !s.hasFix) {
      return 'Waiting for the first GPS reading… Being outdoors helps.';
    }
    final since = s.sinceUpdate;
    final parts = <String>[];
    if (s.mode == CatMode.lost) {
      parts.add(since == null ? 'No reliable position yet' : 'Last good position ${ago(since)}');
      parts.add('±${s.accuracy.round()} m now');
    } else {
      if (since != null) parts.add(since.inSeconds <= 2 ? 'Updated just now' : 'Updated ${ago(since)}');
      parts.add('±${s.accuracy.round()} m');
      if (s.moving) parts.add('${(s.speed * 3.6).toStringAsFixed(1)} km/h');
      if (s.officePhase == PlacePhase.dwelling) parts.add('near the office…');
      if (s.homePhase == PlacePhase.dwelling) parts.add('near home…');
    }
    return parts.join(' · ');
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: GoliTheme.red, shape: BoxShape.circle),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
        elevation: 6,
        shadowColor: Colors.black38,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 12, 8), child: child),
      );
}

class _Banners extends StatelessWidget {
  const _Banners({required this.trip, required this.onShare});
  final TripController trip;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    switch (trip.problem) {
      case LocationProblem.serviceOff:
        items.add(_Banner(
            icon: Icons.location_off_outlined,
            text: 'Location is off. GoliCat is waiting at the last place it saw you.',
            action: 'Turn on',
            onAction: trip.permissions.openLocationSettings));
      case LocationProblem.approximate:
        items.add(_Banner(
            icon: Icons.blur_on,
            text: 'Approximate location only: GoliCat can\'t tell which street you\'re on.',
            action: 'Precise',
            onAction: trip.permissions.openAppSettings));
      case LocationProblem.denied:
      case LocationProblem.deniedForever:
        items.add(_Banner(
            icon: Icons.gpp_maybe_outlined,
            text: 'Location permission is off.',
            action: 'Settings',
            onAction: trip.permissions.openAppSettings));
      case LocationProblem.error:
        items.add(const _Banner(icon: Icons.error_outline, text: 'The phone stopped sending locations. Retrying…'));
      case LocationProblem.none:
        break;
    }
    if (trip.active && trip.shareActive) {
      items.add(_Banner(
        icon: trip.shareFailing ? Icons.cloud_off_outlined : Icons.share_location,
        text: trip.shareFailing
            ? 'Sharing live, but no internet right now. Retrying…'
            : trip.shareUntilTripEnds
                ? 'Sharing your live location until you end the trip.'
                : 'Sharing your live location until ${_hm(trip.shareUntil!)}.',
        action: 'Manage',
        onAction: onShare,
      ));
    }
    if (trip.active && trip.status != null) {
      items.add(const _Banner(
          icon: Icons.lock_clock_outlined,
          text: 'Keeps roaming when the app is closed or locked. Tap End trip to stop.',
          subtle: true));
    }
    return Column(children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: w)]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action, this.onAction, this.subtle = false});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: subtle ? cs.surface.withValues(alpha: 0.92) : const Color(0xFFFFF1D6),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      ),
    );
  }
}

class _PlaceEditor extends StatelessWidget {
  const _PlaceEditor({
    required this.draft,
    required this.canUseCurrent,
    required this.onUseCurrent,
    required this.onRadius,
    required this.onSave,
    required this.onCancel,
    this.onRemove,
  });
  final _PlaceDraft draft;
  final bool canUseCurrent;
  final VoidCallback onUseCurrent, onSave, onCancel;
  final VoidCallback? onRemove;
  final ValueChanged<double> onRadius;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final office = draft.kind == PlaceKind.office;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(office ? 'My office' : 'My home', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          office
              ? 'Stay inside the circle for about 2 minutes and GoliCat clocks in. Tap the map to move the pin.'
              : 'Stay inside the circle for about 2 minutes and GoliCat goes to sleep. Tap the map to move the pin.',
          style: t.bodySmall,
        ),
        Row(children: [
          Text('${draft.radius.round()} m', style: t.labelLarge),
          Expanded(
            child: Slider(
              value: draft.radius.clamp(30, 400),
              min: 30,
              max: 400,
              divisions: 37,
              label: '${draft.radius.round()} m',
              onChanged: onRadius,
            ),
          ),
        ]),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: canUseCurrent ? onUseCurrent : null,
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Use my current location'),
          ),
          if (onRemove != null) TextButton(onPressed: onRemove, child: const Text('Remove')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: onSave, child: const Text('Save'))),
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }
}

class _WhyLocationSheet extends StatelessWidget {
  const _WhyLocationSheet();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GoliCat needs your location', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('• To put the cat on the street you\'re actually on, and walk, wait or zoom when you do.'),
          const SizedBox(height: 6),
          const Text('• Your location stays on this phone. No account, no uploads, no public feed.'),
          const SizedBox(height: 6),
          const Text('• Tracking runs only while a trip is on. End trip stops it completely.'),
          const SizedBox(height: 6),
          const Text('• Choose "Precise" and "While using the app" when your phone asks.'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))),
          ]),
        ]),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.store, required this.trip, required this.onEditHome, required this.onDemo});
  final AppStore store;
  final TripController trip;
  final VoidCallback onEditHome, onDemo;
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ListTile(
            leading: Icon(Icons.lock_clock_outlined),
            title: Text('Trips keep going when the app is closed'),
            subtitle: Text(
                'Like Maps\' location sharing: a "GoliCat is roaming" notification stays until you end the trip. '
                'On Xiaomi/Redmi, Oppo, Vivo and Realme phones also allow Autostart and set Battery saver to '
                '"No restrictions" for GoliCat, or the phone may still stop it.'),
          ),
          SwitchListTile(
            title: const Text('Reduced motion'),
            subtitle: const Text('Smaller bobs and jumps, no line wobble. Every pose stays the same.'),
            value: s.reducedMotion,
            onChanged: (v) => setState(() => s.reducedMotion = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text('Cat size', style: t.bodyLarge),
              const Spacer(),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('S')),
                  ButtonSegment(value: 1, label: Text('M')),
                  ButtonSegment(value: 2, label: Text('L')),
                ],
                selected: {s.catSize},
                onSelectionChanged: (v) => setState(() => s.catSize = v.first),
              ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.bed_outlined),
            title: const Text('My home'),
            subtitle: Text(s.place(PlaceKind.home) == null ? 'Not set: long-press the map' : 'Set · tap to adjust'),
            onTap: widget.onEditHome,
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Demo mode'),
            subtitle: const Text('Simulated walk, tea, office and home. No location needed.'),
            onTap: widget.onDemo,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Your office, home and trips are stored only on this phone.'),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Start, resend or stop a live share.
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.trip});
  final TripController trip;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  static const _choices = <(String, Duration?)>[
    ('15 min', Duration(minutes: 15)),
    ('1 hour', Duration(hours: 1)),
    ('4 hours', Duration(hours: 4)),
    ('Until trip ends', null),
  ];
  int _pick = 1;
  bool _busy = false;
  String? _error;


  @override
  void initState() {
    super.initState();
    widget.trip.addListener(_changed);
  }

  @override
  void dispose() {
    widget.trip.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final trip = widget.trip;
    final link = trip.shareLink;
    if (link == null) return;
    final when = trip.shareUntilTripEnds ? 'until my trip ends' : 'until ${_hm(trip.shareUntil!)}';
    await SharePlus.instance.share(ShareParams(
      text: 'Watch me roam live with GoliCat 🐈 ($when):\n$link',
      subject: 'My live location on GoliCat',
    ));
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final link = await widget.trip.startShare(duration: _choices[_pick].$2);
    if (!mounted) return;
    setState(() => _busy = false);
    if (link == null) {
      setState(() => _error = 'Couldn\'t reach the GoliCat server. Check your internet and try again.');
      return;
    }
    await _send();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final trip = widget.trip;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(trip.shareActive ? 'Sharing your live location' : 'Share your live location',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (!trip.shareActive) ...[
            Text(
              'Anyone with the link sees GoliCat moving on a map in real time, in their browser. '
              'No app needed. Every share gets a new link, and only your latest position is kept. '
              'It is deleted when sharing stops.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 14),
            Text('Share for', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (var i = 0; i < _choices.length; i++)
                ChoiceChip(
                  label: Text(_choices[i].$1),
                  selected: _pick == i,
                  onSelected: (_) => setState(() => _pick = i),
                ),
            ]),
          ] else ...[
            Text(
              trip.shareUntilTripEnds
                  ? 'Live until you end this trip (at most 12 hours).'
                  : 'Live until ${_hm(trip.shareUntil!)}. Ending the trip also stops sharing.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 10),
            SelectableText(trip.shareLink!, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            if (trip.shareFailing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No internet right now: viewers see your last position until it reconnects.',
                    style: t.bodySmall?.copyWith(color: GoliTheme.red)),
              ),
          ],
          const SizedBox(height: 8),
          Text('Sharing keeps running when the app is closed or the phone is locked, until it expires or you end the trip.',
              style: t.bodySmall),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: t.bodySmall?.copyWith(color: GoliTheme.red)),
            ),
          const SizedBox(height: 4),
          if (!trip.shareActive)
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share_location),
              label: Text(_busy ? 'Making your link…' : 'Start sharing & send link'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await trip.stopShare();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop sharing'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Send link'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}
