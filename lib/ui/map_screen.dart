import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cat/cat_layer.dart';
import '../cat/cat_skin.dart';
import '../core/geo.dart';
import '../places/custom_place.dart';
import '../places/place_store.dart';
import '../share/share_controller.dart';
import '../tracking/activity_engine.dart';
import '../tracking/location_service.dart';
import '../tracking/place_monitor.dart';
import '../tracking/trip_recorder.dart';
import '../tracking/trip_runner.dart';
import '../update/update_dialog.dart';
import '../update/updater.dart';
import 'avatar_screen.dart';
import 'busy.dart';
import 'comic_screen.dart';
import 'theme.dart';
import 'trip_controller.dart';

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

/// Pin look for each kind of place.
({IconData icon, IconData outlined, Color color}) _pinOf(PlaceKind k) => switch (k) {
      PlaceKind.office => (icon: Icons.business_center, outlined: Icons.business_center_outlined, color: GoliTheme.red),
      PlaceKind.home => (icon: Icons.bed, outlined: Icons.bed_outlined, color: const Color(0xFF2F5D8A)),
      PlaceKind.education => (icon: Icons.school, outlined: Icons.school_outlined, color: const Color(0xFF2F8F6B)),
      PlaceKind.hangout => (icon: Icons.headphones, outlined: Icons.headphones_outlined, color: const Color(0xFF6C63FF)),
    };
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
  _PlaceDraft(this.kind, this.center, this.radius, {required this.existing, this.custom});

  /// One of the four places the cat reacts to, or null for a custom place.
  final PlaceKind? kind;

  /// The custom place being added or edited (name and icon).
  CustomPlace? custom;
  GeoPoint center;
  double radius;
  final bool existing;
}

/// What the place chooser returns for "More places".
const _more = 'more';

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TripController trip = TripController(widget.store);
  final projector = OsmProjector();
  final _map = MapController();
  bool _mapReady = false;
  bool _follow = true;
  _PlaceDraft? _draft;
  GeoPoint? _lastCameraTarget;

  // Smooth camera glide (flutter_map moves instantly by itself).
  late final AnimationController _glide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  LatLng? _glideFrom, _glideTo;
  double _glideZoomFrom = 0, _glideZoomTo = 0;

  static const _dhaka = LatLng(23.7806, 90.4000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    trip.addListener(_onTrip);
    _glide.addListener(() {
      if (_glideFrom == null || _glideTo == null || !_mapReady) return;
      final t = Curves.easeInOut.transform(_glide.value);
      final lat = _glideFrom!.latitude + (_glideTo!.latitude - _glideFrom!.latitude) * t;
      final lng = _glideFrom!.longitude + (_glideTo!.longitude - _glideFrom!.longitude) * t;
      _map.move(LatLng(lat, lng), _glideZoomFrom + (_glideZoomTo - _glideZoomFrom) * t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach().whenComplete(_checkForUpdate));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      trip.recheckProblem();
      // Left open for hours: look again, the way other apps do on reopening.
      final last = _updateCheckedAt;
      if (last != null && DateTime.now().difference(last) > const Duration(hours: 6)) _checkForUpdate();
    }
  }

  // ---- updates ---------------------------------------------------------------

  DateTime? _updateCheckedAt;
  bool _updateShowing = false;

  /// Asks once per opening when the download page has a newer version.
  /// Nothing downloads unless the user taps Update.
  Future<void> _checkForUpdate() async {
    if (!Updater.supported || _updateShowing) return;
    _updateCheckedAt = DateTime.now();
    final updater = Updater();
    final info = await updater.check();
    if (info == null || !mounted || _updateShowing) {
      if (info == null) await updater.cleanup();
      updater.dispose();
      return;
    }
    _updateShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updater: updater, info: info),
    );
    _updateShowing = false;
    updater.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final updated = widget.store.updatedFrom != null;
    widget.store.updatedFrom = null;
    final log = await trip.interruptedTrip();
    if (log == null || !mounted) return;
    final alive = widget.store.tripAliveAt;
    final justNow = alive != null && DateTime.now().difference(alive).abs() < const Duration(minutes: 15);
    if (updated && justNow) {
      // The update stopped a running trip a moment ago: carry on where it was,
      // same journal, same live-share link, instead of asking. (A trip that
      // died long before the update still gets the question below.)
      await widget.store.setTripRunning(true);
      final p = await trip.start(resume: true);
      if (!mounted) return;
      if (p == LocationProblem.none || p == LocationProblem.approximate) {
        _snack('GoliCat updated. Your trip carries on.');
        return;
      }
    }
    await showDialog<void>(
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
              _stopLeftoverShare();
              Navigator.pop(ctx);
            },
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () {
              widget.store.saveActiveTrip(null);
              _stopLeftoverShare();
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
    // No setState here: the parts that show trip state listen to [trip]
    // themselves, so the map and its tiles are not rebuilt twice a second.
  }

  // ---- actions -------------------------------------------------------------

  Future<void> _startRoaming() async {
    if (trip.state == TripState.starting) return;
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
    final kind = await _choosePlaceKind(settingHere: true);
    if (kind == null || !mounted) return;
    if (kind == _more) return _addCustomPlace(at: _gp(at));
    _editPlace(kind as PlaceKind, at: _gp(at));
  }

  Future<Object?> _choosePlaceKind({bool settingHere = false}) {
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          for (final k in PlaceKind.values)
            ListTile(
              leading: Icon(_pinOf(k).outlined, color: _pinOf(k).color),
              title: Text(settingHere ? 'Set as ${k.title.substring(3).toLowerCase()}' : k.title),
              subtitle: Text(settingHere
                  ? k.blurb
                  : widget.store.place(k) == null
                      ? '${k.blurb} · not set'
                      : '${k.blurb} · set'),
              onTap: () => Navigator.pop(ctx, k),
            ),
          if (!settingHere)
            for (final c in widget.store.customPlaces)
              ListTile(
                leading: Icon(c.look.icon, color: c.look.color),
                title: Text(c.name),
                subtitle: const Text('Your own pin · tap to adjust'),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ListTile(
            leading: const Icon(Icons.add_location_alt_outlined),
            title: const Text('More places'),
            subtitle: const Text("Hospital, shop, mosque, a friend's house… pick an icon and name it"),
            onTap: () => Navigator.pop(ctx, _more),
          ),
          const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickPlaceToEdit() async {
    final pick = await _choosePlaceKind();
    if (pick == null || !mounted) return;
    if (pick == _more) return _addCustomPlace();
    if (pick is CustomPlace) return _editCustom(pick);
    _editPlace(pick as PlaceKind);
  }

  /// "More": choose an icon and a name, then put the pin on the map.
  Future<void> _addCustomPlace({GeoPoint? at}) async {
    if (widget.store.customPlaces.length >= CustomPlace.maxCount) {
      _snack('You can keep up to ${CustomPlace.maxCount} of your own places. Remove one to add another.');
      return;
    }
    final center = at ?? trip.position ?? (_mapReady ? _gp(_map.camera.center) : null);
    if (center == null) return;
    final picked = await _askNameAndIcon();
    if (picked == null || !mounted) return;
    final c = CustomPlace(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: picked.name,
      icon: picked.icon,
      center: center,
    );
    setState(() {
      _follow = false;
      _draft = _PlaceDraft(null, center, 0, existing: false, custom: c);
    });
    _glideTo_(center, zoom: 16.5);
  }

  void _editCustom(CustomPlace c) {
    setState(() {
      _follow = false;
      _draft = _PlaceDraft(null, c.center, 0, existing: true, custom: c);
    });
    _glideTo_(c.center, zoom: 16.5);
  }

  Future<({String name, String icon})?> _askNameAndIcon({CustomPlace? current}) {
    return showModalBottomSheet<({String name, String icon})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CustomPlaceSheet(current: current),
    );
  }

  Future<void> _renameDraft() async {
    final c = _draft?.custom;
    if (c == null) return;
    final picked = await _askNameAndIcon(current: c);
    if (picked == null || !mounted || _draft?.custom?.id != c.id) return;
    setState(() => _draft!.custom = c.copyWith(name: picked.name, icon: picked.icon));
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
      _draft = _PlaceDraft(kind, center, existing?.radiusM ?? kind.defaultRadius, existing: existing != null);
    });
    _glideTo_(center, zoom: 16.5);
  }

  bool _savingPlace = false;

  Future<void> _saveDraft() async {
    if (_savingPlace) return;
    final d = _draft!;
    setState(() => _savingPlace = true);
    final kind = d.kind;
    if (kind == null) {
      final c = d.custom!.copyWith(center: d.center);
      await widget.store.saveCustomPlace(c);
      if (!mounted) return;
      setState(() {
        _savingPlace = false;
        _draft = null;
      });
      _snack('${c.name} saved on this phone.');
      return;
    }
    await widget.store.setPlace(kind, Place(center: d.center, radiusM: d.radius));
    trip.placeChanged(kind);
    if (!mounted) return;
    setState(() {
      _savingPlace = false;
      _draft = null;
    });
    _snack('${kind.title.substring(3)} saved on this phone.');
  }

  Future<void> _removeDraft() async {
    final d = _draft!;
    final kind = d.kind;
    if (kind == null) {
      await widget.store.removeCustomPlace(d.custom!.id);
    } else {
      await widget.store.setPlace(kind, null);
      trip.placeChanged(kind);
    }
    if (mounted) setState(() => _draft = null);
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

  /// A live share that outlived its trip (the phone killed the service) must
  /// stop now, not keep showing the last position until it expires.
  void _stopLeftoverShare() {
    final leftover = ShareController(widget.store);
    if (leftover.active) leftover.stop().whenComplete(leftover.dispose);
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        store: widget.store,
        trip: trip,
        onEditPlace: (k) {
          Navigator.pop(ctx);
          _editPlace(k);
        },
        onEditCustom: (c) {
          Navigator.pop(ctx);
          _editCustom(c);
        },
        onAddCustom: () {
          Navigator.pop(ctx);
          _addCustomPlace();
        },
        onAvatar: () {
          Navigator.pop(ctx);
          _openAvatar();
        },
      ),
    );
  }

  Future<void> _openAvatar() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AvatarScreen(store: widget.store)));
    trip.avatarChanged();
    if (mounted) setState(() {});
  }

  void _openShare() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ShareSheet(trip: trip),
    );
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
      final col = _pinOf(k).color;
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
      final pin = _pinOf(k);
      out.add(Marker(
        point: _ll(v.c),
        width: 40,
        height: 48,
        alignment: Alignment.topCenter,
        child: Semantics(
          button: true,
          label: '${k.title}. Tap to adjust.',
          child: GestureDetector(
            onTap: v.editing ? null : () => _editPlace(k),
            child: _PlacePin(icon: pin.icon, color: pin.color, big: v.editing),
          ),
        ),
      ));
    }
    final d = _draft;
    final editingId = d?.custom?.id;
    final customs = [
      for (final c in widget.store.customPlaces)
        if (c.id != editingId) (c: c, editing: false),
      if (d != null && d.custom != null) (c: d.custom!.copyWith(center: d.center), editing: true),
    ];
    for (final e in customs) {
      final c = e.c;
      out.add(Marker(
        point: _ll(c.center),
        width: 120,
        height: 70,
        // The pin's tip (46 px down a 70 px box) sits on the place itself.
        alignment: const Alignment(0, -0.314),
        child: Semantics(
          button: true,
          label: '${c.name}. Tap to adjust.',
          child: GestureDetector(
            onTap: e.editing ? null : () => _editCustom(c),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _PlacePin(icon: c.look.icon, color: c.look.color, big: e.editing),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.look.color.withValues(alpha: 0.5)),
                ),
                child: Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.look.color)),
              ),
            ]),
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
            ListenableBuilder(
              listenable: trip,
              builder: (context, _) {
                if (!trip.active || trip.position == null) return const SizedBox.shrink();
                projector.camera = MapCamera.of(context);
                return CatLayer(
                  session: trip.mirror,
                  projector: projector,
                  scale: widget.store.catScale,
                  reducedMotion: widget.store.reducedMotion,
                );
              },
            ),
          ],
        ),
        Positioned(
          top: mq.padding.top + 8,
          left: 12,
          right: 12,
          child: ListenableBuilder(listenable: trip, builder: (_, _) => _Banners(trip: trip, onShare: _openShare)),
        ),
        // Recenter button, attribution and the panel stack from the bottom up,
        // so nothing has to be measured or jumps after the first frame.
        Positioned(
          left: 10,
          right: 10,
          bottom: mq.padding.bottom + 10,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            ListenableBuilder(
              listenable: trip,
              builder: (_, _) {
                final show = trip.active && !_follow && _draft == null;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomRight,
                  child: show
                      ? Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 10),
                          child: FloatingActionButton.small(
                            heroTag: 'recenter',
                            tooltip: 'Back to GoliCat',
                            onPressed: _recenter,
                            child: const Icon(Icons.my_location),
                          ),
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 11, color: Color(0xFF333333))),
              ),
            ),
            const SizedBox(height: 4),
            ListenableBuilder(listenable: trip, builder: (context, _) {
              return _draft != null
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
                    saving: _savingPlace,
                    onCancel: () => setState(() => _draft = null),
                    onRemove: _draft!.existing ? _removeDraft : null,
                    onRename: _draft!.custom != null ? _renameDraft : null,
                  )
                : _StatusPanel(
                    trip: trip,
                    onStart: _startRoaming,
                    onEnd: _endTrip,
                    onPlaces: _pickPlaceToEdit,
                    onMore: _openSettings,
                    onAvatar: _openAvatar,
                    onShare: _openShare,
                  );
            }),
          ]),
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

String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

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
    required this.onPlaces,
    required this.onMore,
    required this.onAvatar,
    required this.onShare,
  });
  final TripController trip;
  final VoidCallback onStart, onEnd, onPlaces, onMore, onAvatar, onShare;

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
                onPressed: onStart, // guarded inside; stays bright while busy
                icon: BusyIcon(busy: trip.state == TripState.starting, icon: Icons.pets),
                label: BusyLabel(busy: trip.state == TripState.starting, text: 'Start roaming', busyText: 'Finding you…'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(onPressed: onAvatar, tooltip: 'Choose your cat', icon: const Icon(Icons.face_outlined)),
            const SizedBox(width: 4),
            IconButton.outlined(onPressed: onMore, tooltip: 'Places & settings', icon: const Icon(Icons.tune)),
          ]),
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
              onPressed: onEnd, // guarded inside; stays bright while busy
              icon: BusyIcon(busy: trip.ending, icon: Icons.stop_rounded),
              label: BusyLabel(busy: trip.ending, text: 'End trip', busyText: 'Ending…'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPlaces,
            icon: const Icon(Icons.place_outlined, size: 18),
            label: const Text('Places'),
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
      for (final k in PlaceKind.values) {
        if (s.phase(k) == PlacePhase.dwelling) parts.add('near ${k.title.substring(3).toLowerCase()}…');
      }
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
    // Shown briefly at the start of a trip, then it gets out of the map's way.
    final started = trip.status?.startedAt;
    if (trip.active && started != null && DateTime.now().difference(started) < const Duration(seconds: 25)) {
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
    this.onRename,
    this.saving = false,
  });
  final _PlaceDraft draft;
  final VoidCallback? onRename;
  final bool saving;
  final bool canUseCurrent;
  final VoidCallback onUseCurrent, onSave, onCancel;
  final VoidCallback? onRemove;
  final ValueChanged<double> onRadius;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = draft.kind;
    final custom = draft.custom;
    final icon = kind != null ? _pinOf(kind).icon : custom!.look.icon;
    final color = kind != null ? _pinOf(kind).color : custom!.look.color;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(kind?.title ?? custom!.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (onRename != null) TextButton(onPressed: onRename, child: const Text('Name & icon')),
        ]),
        Text(
          kind != null
              ? 'Stay inside the circle for about 2 minutes and ${kind.arrivalText}. Tap the map to move the pin.'
              : 'Tap the map to move the pin. It stays on your map, saved on this phone.',
          style: t.bodySmall,
        ),
        if (kind != null) Row(children: [
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
          Expanded(
            child: FilledButton.icon(
              onPressed: onSave,
              icon: BusyIcon(busy: saving, icon: Icons.check),
              label: BusyLabel(busy: saving, text: 'Save', busyText: 'Saving…'),
            ),
          ),
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
          const Text('• Your location stays on this phone unless you start a live share, and then only for as long as you choose. No account, no public feed.'),
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
  const _SettingsSheet({
    required this.store,
    required this.trip,
    required this.onEditPlace,
    required this.onEditCustom,
    required this.onAddCustom,
    required this.onAvatar,
  });
  final AppStore store;
  final TripController trip;
  final ValueChanged<PlaceKind> onEditPlace;
  final ValueChanged<CustomPlace> onEditCustom;
  final VoidCallback onAddCustom;
  final VoidCallback onAvatar;
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
          ListTile(
            leading: const Icon(Icons.face_outlined),
            title: const Text('Choose your cat'),
            subtitle: Text('Now: ${CatSkin.byId(s.catSkinId).name}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAvatar,
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text('My places', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final k in PlaceKind.values)
            ListTile(
              leading: Icon(_pinOf(k).outlined, color: _pinOf(k).color),
              title: Text(k.title),
              subtitle: Text(s.place(k) == null ? '${k.blurb} · not set, long-press the map' : '${k.blurb} · set, tap to adjust'),
              onTap: () => widget.onEditPlace(k),
            ),
          for (final c in s.customPlaces)
            ListTile(
              leading: Icon(c.look.icon, color: c.look.color),
              title: Text(c.name),
              subtitle: const Text('Your own pin · tap to adjust'),
              onTap: () => widget.onEditCustom(c),
            ),
          ListTile(
            leading: const Icon(Icons.add_location_alt_outlined),
            title: const Text('More places'),
            subtitle: const Text('Pin a hospital, shop, mosque… with your own name'),
            onTap: widget.onAddCustom,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Your places and trips are stored only on this phone.'),
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
  bool _busy = false, _sending = false;
  String? _error;

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.trip.stopShare();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);
  }


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
    if (link == null || _sending) return;
    setState(() => _sending = true);
    final when = trip.shareUntilTripEnds ? 'until my trip ends' : 'until ${_hm(trip.shareUntil!)}';
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'Watch me roam live with GoliCat 🐈 ($when):\n$link',
        subject: 'My live location on GoliCat',
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
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
              onPressed: _start,
              icon: BusyIcon(busy: _busy, icon: Icons.share_location),
              label: BusyLabel(busy: _busy, text: 'Start sharing & send link', busyText: 'Making your link…'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stop,
                  icon: BusyIcon(busy: _busy, icon: Icons.stop_circle_outlined),
                  label: BusyLabel(busy: _busy, text: 'Stop sharing', busyText: 'Stopping…'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _send,
                  icon: BusyIcon(busy: _sending, icon: Icons.send),
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

// ---------------------------------------------------------------------------

/// "More places": a name typed in Bangla or English, and an icon.
class _CustomPlaceSheet extends StatefulWidget {
  const _CustomPlaceSheet({this.current});
  final CustomPlace? current;
  @override
  State<_CustomPlaceSheet> createState() => _CustomPlaceSheetState();
}

class _CustomPlaceSheetState extends State<_CustomPlaceSheet> {
  late final _name = TextEditingController(text: widget.current?.name ?? '');
  late String _icon = widget.current?.icon ?? placeIcons.first.key;

  /// The name we filled in from an icon, so picking another icon can replace it.
  String? _suggested;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _pick(PlaceIcon i) {
    setState(() {
      _icon = i.key;
      final typed = _name.text.trim();
      if (typed.isEmpty || typed == _suggested) {
        _suggested = i.suggestedName;
        _name.text = i.suggestedName;
        _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
  }

  void _done() {
    final name = _name.text.trim();
    Navigator.pop(context, (name: name.isEmpty ? placeIconOf(_icon).suggestedName : name, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.current == null ? 'Add a place' : 'Name & icon',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: CustomPlace.maxName,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _done(),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'যেমন: আম্মুর বাসা / Gym',
                border: OutlineInputBorder(),
              ),
            ),
            Text('Icon', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in placeIcons)
                Semantics(
                  button: true,
                  selected: i.key == _icon,
                  label: i.en,
                  child: InkResponse(
                    onTap: () => _pick(i),
                    radius: 28,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: i.key == _icon ? i.color : i.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: i.color.withValues(alpha: i.key == _icon ? 1 : 0.35), width: 2),
                      ),
                      child: Icon(i.icon, color: i.key == _icon ? Colors.white : i.color, size: 22),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _done,
              icon: Icon(widget.current == null ? Icons.add_location_alt : Icons.check),
              label: Text(widget.current == null ? 'Put it on the map' : 'Done'),
            ),
          ]),
        ),
      ),
    );
  }
}
