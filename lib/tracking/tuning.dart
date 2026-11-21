/// Every threshold the engines use, in one place so they can be tuned.
class Tuning {
  const Tuning({
    this.reliableAccuracyM = 35,
    this.degradedAccuracyM = 90,
    this.placeAccuracyM = 50,
    this.staleAfter = const Duration(seconds: 25),
    this.staleAfterSlowSampling = const Duration(seconds: 50),
    this.moveConfirmFixes = 3,
    this.moveConfirmSpan = const Duration(seconds: 2),
    this.moveRadiusMinM = 10,
    this.stopWindow = const Duration(seconds: 18),
    this.stopSpreadM = 14,
    this.stopSpeed = 0.5,
    this.fastSpeed = 3.4,
    this.fastExitSpeed = 2.6,
    this.maxPlausibleSpeed = 70,
    this.teaDelay = const Duration(seconds: 60),
    this.slowSamplingAfter = const Duration(seconds: 90),
    this.placeDwell = const Duration(minutes: 2),
    this.placePassWindow = const Duration(seconds: 60),
    this.placePassMaxNetM = 30,
    this.placeOutsideGrace = const Duration(seconds: 30),
    this.placeExitConfirm = const Duration(seconds: 15),
  });

  /// Fixes worse than this never move the cat…
  final double reliableAccuracyM;

  /// …unless no reliable fix has come for [staleAfter]: then fixes up to this
  /// accuracy are followed too, so losing the network (and assisted GPS)
  /// degrades the track instead of freezing the cat.
  final double degradedAccuracyM;

  /// Fixes worse than this are ignored by office/home detection.
  final double placeAccuracyM;

  /// No reliable fix for this long: the cat gets out its paper map.
  final Duration staleAfter;
  final Duration staleAfterSlowSampling;

  /// Consecutive, consistent fixes outside the rest circle needed to start moving.
  final int moveConfirmFixes;
  final Duration moveConfirmSpan;
  final double moveRadiusMinM;

  /// Stop is declared when every fix in this window sits inside [stopSpreadM].
  final Duration stopWindow;
  final double stopSpreadM;
  final double stopSpeed;

  /// m/s. 3.4 m/s is about 12 km/h: faster than a brisk walk.
  final double fastSpeed;
  final double fastExitSpeed;

  /// Anything faster between two fixes is a GPS glitch.
  final double maxPlausibleSpeed;

  /// Standing still this long: cha break.
  final Duration teaDelay;

  /// Standing still this long: the phone samples less often.
  final Duration slowSamplingAfter;

  /// Office / home: time inside the circle before arrival counts.
  final Duration placeDwell;

  /// Passing by: if you moved more than [placePassMaxNetM] in this window,
  /// you are walking past, not arriving.
  final Duration placePassWindow;
  final double placePassMaxNetM;

  /// While waiting to arrive, a short excursion outside the circle is forgiven.
  final Duration placeOutsideGrace;

  /// After arriving, you must be beyond the wider exit ring for this long.
  final Duration placeExitConfirm;

  /// Exit ring is wider than the arrival ring so indoor drift can't flip-flop.
  static double exitRadiusFor(double radius) =>
      radius + (radius * 0.3 < 30 ? 30 : radius * 0.3);
}
