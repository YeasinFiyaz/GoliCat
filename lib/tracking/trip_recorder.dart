import 'dart:convert';

import '../cat/clips.dart';
import '../core/geo.dart';
import 'activity_engine.dart';

/// A journal of what the cat did on a trip. It deliberately stores NO
/// coordinates or routes: only moments, durations and total distance.
class TripLog {
  TripLog({required this.startedAt});

  final DateTime startedAt;
  DateTime? endedAt;
  double distanceM = 0;
  final List<TripMoment> moments = [];

  void addClip(ClipId c, DateTime at) {
    if (moments.isNotEmpty && moments.last.clip == c) return;
    moments.add(TripMoment(c, at.difference(startedAt)));
  }

  /// How long each loop lasted (until the next moment).
  Duration durationOf(int i) {
    final end = i + 1 < moments.length
        ? moments[i + 1].offset
        : (endedAt ?? DateTime.now()).difference(startedAt);
    return end - moments[i].offset;
  }

  String toJson() => jsonEncode({
        's': startedAt.toIso8601String(),
        'd': distanceM,
        'm': [for (final m in moments) [m.clip.name, m.offset.inSeconds]],
      });

  static TripLog? fromJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final log = TripLog(startedAt: DateTime.parse(j['s'] as String));
      log.distanceM = (j['d'] as num).toDouble();
      for (final m in (j['m'] as List)) {
        final l = m as List;
        log.moments.add(TripMoment(ClipId.values.byName(l[0] as String), Duration(seconds: l[1] as int)));
      }
      return log;
    } catch (_) {
      return null;
    }
  }
}

class TripMoment {
  TripMoment(this.clip, this.offset);
  final ClipId clip;
  final Duration offset;
}

/// Adds distance only while moving, using the engine's smoothed track.
class DistanceMeter {
  GeoPoint? _last;
  double add(ActivitySnapshot s) {
    final p = s.position;
    if (p == null) return 0;
    if (!s.motion.moving) {
      _last = p;
      return 0;
    }
    final last = _last;
    _last = p;
    if (last == null) return 0;
    final d = distanceM(last, p);
    return d < 200 ? d : 0;
  }
}

/// One panel of the end-of-trip comic.
class ComicPanel {
  const ComicPanel(this.clip, this.t, this.caption);
  final ClipId clip;

  /// Moment within the clip to freeze.
  final double t;
  final String caption;
}

/// Picks departure / most memorable pause / ending from what actually happened.
List<ComicPanel> comicFor(TripLog log) {
  final clips = log.moments.map((m) => m.clip).toList();

  ComicPanel departure;
  if (clips.contains(ClipId.wakeUp)) {
    departure = const ComicPanel(ClipId.wakeUp, 1.2, 'Big stretch. Off we go!');
  } else if (clips.contains(ClipId.leaveOffice)) {
    departure = const ComicPanel(ClipId.leaveOffice, 0.55, 'Glasses on the monitor. Bye, desk!');
  } else if (clips.contains(ClipId.closeBook)) {
    departure = const ComicPanel(ClipId.closeBook, 0.3, 'Pencil down. Off we go.');
  } else if (clips.contains(ClipId.headphonesOff)) {
    departure = const ComicPanel(ClipId.headphonesOff, 0.2, 'One last song, then off.');
  } else if (clips.contains(ClipId.walk) || clips.contains(ClipId.catchUp)) {
    departure = const ComicPanel(ClipId.walk, 0.12, 'Into the goli we go.');
  } else if (clips.contains(ClipId.fast)) {
    departure = const ComicPanel(ClipId.fast, 0.1, 'Straight into top speed.');
  } else {
    departure = const ComicPanel(ClipId.idle, 2.6, 'GoliCat checks the street…');
  }

  // Most memorable pause: longest cha break, then gags, then other moments.
  ComicPanel? pause;
  Duration best = Duration.zero;
  for (var i = 0; i < log.moments.length; i++) {
    if (log.moments[i].clip == ClipId.tea && log.durationOf(i) > best) {
      best = log.durationOf(i);
    }
  }
  if (best > Duration.zero) {
    final mins = best.inMinutes;
    pause = ComicPanel(ClipId.tea, 2.6, mins >= 1 ? 'A $mins-minute cha break. Worth it.' : 'A quick sip of cha.');
  } else if (clips.contains(ClipId.fishGag)) {
    pause = const ComicPanel(ClipId.fishGag, 1.4, 'A fish?! On the screen?!');
  } else if (clips.contains(ClipId.danceGag)) {
    pause = const ComicPanel(ClipId.danceGag, 0.9, 'This is the good bit!');
  } else if (clips.contains(ClipId.stuckGag)) {
    pause = const ComicPanel(ClipId.stuckGag, 1.0, 'Stuck on a sum. Classic.');
  } else if (clips.contains(ClipId.vibe)) {
    pause = const ComicPanel(ClipId.vibe, 1.2, 'Headphones on. Dhaka fades away.');
  } else if (clips.contains(ClipId.jam)) {
    pause = const ComicPanel(ClipId.jam, 1.2, 'Stuck in a jam. Put a song on.');
  } else if (clips.contains(ClipId.lost)) {
    pause = const ComicPanel(ClipId.lost, 0.8, 'Lost the signal. Consulted the map.');
  } else if (clips.contains(ClipId.skid)) {
    pause = const ComicPanel(ClipId.skid, 0.9, 'Skrrrt! Scarf in the face.');
  } else if (clips.contains(ClipId.batPin)) {
    pause = const ComicPanel(ClipId.batPin, 0.5, 'Bopped its own map pin.');
  } else if (clips.contains(ClipId.grumpy)) {
    pause = const ComicPanel(ClipId.grumpy, 1.4, 'Five more minutes…');
  }
  pause ??= const ComicPanel(ClipId.catchUp, 0.4, 'No stops this time. Straight on!');

  ComicPanel ending;
  final last = clips.isEmpty ? ClipId.idle : clips.last;
  switch (last) {
    case ClipId.typing:
    case ClipId.hopOnChair:
    case ClipId.fishGag:
      ending = const ComicPanel(ClipId.typing, 4.74, 'কাজে আছি. ENTER!');
    case ClipId.sleep:
    case ClipId.tuckIn:
    case ClipId.grumpy:
      ending = const ComicPanel(ClipId.sleep, 1.6, 'Home. Under the kantha. Zzz…');
    case ClipId.tea:
    case ClipId.sitDown:
      ending = const ComicPanel(ClipId.tea, 2.6, 'Ended with a cha. Naturally.');
    case ClipId.lost:
    case ClipId.unfoldMap:
      ending = const ComicPanel(ClipId.lost, 2.4, 'Journey\'s end… somewhere?');
    case ClipId.study:
    case ClipId.sitAtDesk:
    case ClipId.stuckGag:
      ending = const ComicPanel(ClipId.study, 3.2, 'পড়ছি. Homework done. Probably.');
    case ClipId.vibe:
    case ClipId.headphonesOn:
    case ClipId.danceGag:
      ending = const ComicPanel(ClipId.vibe, 0.9, 'আড্ডা. Still vibing when the trip ended.');
    case ClipId.jam:
    case ClipId.jamOn:
    case ClipId.jamDance:
      ending = const ComicPanel(ClipId.jam, 1.2, 'জ্যাম. Still stuck when the trip ended.');
    case ClipId.fast:
      ending = const ComicPanel(ClipId.fast, 0.2, 'Still zooming when the trip ended.');
    case ClipId.walk:
    case ClipId.catchUp:
    case ClipId.stashTea:
    case ClipId.leaveOffice:
    case ClipId.wakeUp:
      ending = const ComicPanel(ClipId.walk, 0.3, 'Still trotting. Trip over!');
    default:
      ending = const ComicPanel(ClipId.idle, 0.2, 'Journey\'s end.');
  }
  return [departure, pause, ending];
}
