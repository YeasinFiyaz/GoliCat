import 'dart:async';

import '../places/place_store.dart';
import '../share/share_controller.dart';
import 'trip_runner.dart';

/// Where the trip actually runs. The UI only ever talks to one of these:
/// plain-map commands in, plain-map status out, so the same screen works
/// whether the trip lives in the Android foreground service or in-process.
///
/// Commands: `start` {resume}, `stop`, `startShare` {minutes?}, `stopShare`,
/// `place` {kind}, `avatar` (re-read the chosen cat), `status` (asks for a fresh status event).
abstract class TripBackend {
  Stream<Map<String, dynamic>> get status;
  Future<bool> isRunning();
  Future<void> send(String command, [Map<String, dynamic>? args]);
  Future<void> dispose();
}

/// Runs the trip inside this process (iOS, desktop, tests).
class LocalBackend implements TripBackend {
  LocalBackend(this.store, {LocationSource? location, ShareController? share, DateTime Function()? clock})
      : runner = TripRunner(store, location: location, share: share, clock: clock) {
    runner.onStatus = _events.add;
  }

  final AppStore store;
  final TripRunner runner;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get status => _events.stream;

  @override
  Future<bool> isRunning() async => runner.running;

  @override
  Future<void> send(String command, [Map<String, dynamic>? args]) => handle(runner, command, args);

  /// Shared by both backends: maps a command onto the runner.
  static Future<void> handle(TripRunner runner, String command, Map<String, dynamic>? args) async {
    switch (command) {
      case 'start':
        await runner.start(resume: args?['resume'] == true);
      case 'stop':
        await runner.stop();
      case 'startShare':
        await runner.store.reload(); // pick up the avatar chosen in the app
        final m = args?['minutes'];
        await runner.startShare(duration: m == null ? null : Duration(minutes: (m as num).toInt()));
      case 'stopShare':
        await runner.stopShare();
      case 'place':
        await runner.store.reload();
        runner.placeChanged(PlaceKind.values.firstWhere((k) => k.name == args?['kind']));
      case 'avatar':
        await runner.store.reload(); // the share sends the avatar id with every push
      case 'status':
        runner.emit();
    }
  }

  @override
  Future<void> dispose() async {
    await runner.dispose();
    await _events.close();
  }
}
