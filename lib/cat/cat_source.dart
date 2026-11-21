import '../core/position_glide.dart';
import 'cat_director.dart';

/// Anything that can drive a cat on a map: a real trip, the demo, or a live
/// share being watched in the browser.
abstract class CatSource {
  PositionGlide get position;
  CatDirector get director;
  bool get moving;
  double get headingDeg;
}
