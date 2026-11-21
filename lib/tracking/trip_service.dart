import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../places/place_store.dart';
import 'trip_backend.dart';
import 'trip_runner.dart';

/// The Android foreground service that carries a trip while the app is
/// closed, swiped away or the screen is locked (like Maps' location sharing).
/// It owns the only [TripRunner]; the app's screen is just a mirror of it.
class ServiceBackend implements TripBackend {
  ServiceBackend(this.store);

  final AppStore store;
  final _svc = FlutterBackgroundService();
  bool _configured = false;

  static const notificationChannel = 'golicat_trip';

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannel,
        initialNotificationTitle: 'GoliCat is roaming with you',
        initialNotificationContent: 'Finding you…',
        foregroundServiceNotificationId: 7001,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(autoStart: false, onForeground: onServiceStart, onBackground: (_) => true),
    );
  }

  @override
  Stream<Map<String, dynamic>> get status =>
      _svc.on('status').where((e) => e != null).map((e) => Map<String, dynamic>.from(e!));

  @override
  Future<bool> isRunning() async {
    await _configure();
    return _svc.isRunning();
  }

  @override
  Future<void> send(String command, [Map<String, dynamic>? args]) async {
    await _configure();
    if (command == 'start') {
      // The service reads this flag when it boots, so the start can't be lost
      // in the gap before its listeners exist. Also what makes it resume after
      // Android restarts it.
      await store.setTripRunning(true);
      if (args?['resume'] != true) await store.saveActiveTrip(null);
      if (!await _svc.isRunning()) {
        await _svc.startService();
        return;
      }
    }
    _svc.invoke(command, args);
  }

  @override
  Future<void> dispose() async {}
}

/// Entry point of the background isolate. Everything here runs without UI.
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final store = await AppStore.load();
  final runner = TripRunner(store);
  String lastNote = '';

  runner.onStatus = (st) {
    service.invoke('status', st);
    if (service is AndroidServiceInstance) {
      final note = runner.notificationText();
      if (note != lastNote) {
        lastNote = note;
        service.setForegroundNotificationInfo(title: 'GoliCat is roaming with you', content: note);
      }
    }
    if (st['running'] == false) {
      // Trip over (user ended it, or the 24 h limit): the notification goes too.
      Future<void>.delayed(const Duration(milliseconds: 300), service.stopSelf);
    }
  };

  for (final cmd in ['start', 'stop', 'startShare', 'stopShare', 'place', 'avatar', 'status']) {
    service.on(cmd).listen((args) async {
      try {
        await LocalBackend.handle(runner, cmd, args == null ? null : Map<String, dynamic>.from(args));
      } catch (e) {
        debugPrint('trip service $cmd failed: $e');
      }
    });
  }

  if (store.tripRunning) {
    // Fresh start from the app, or Android brought the service back: carry on.
    try {
      await runner.start(resume: true);
    } catch (e) {
      debugPrint('trip service start failed: $e');
    }
    if (!runner.running) {
      await store.setTripRunning(false);
      service.invoke('status', runner.status());
      await service.stopSelf();
    }
  } else {
    await service.stopSelf();
  }
}
