import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/place_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the map remembers where the phone was, across restarts', () async {
    SharedPreferences.setMockInitialValues({'seeded': true});
    var s = await AppStore.load();
    expect(s.lastPosition, isNull);
    await s.setLastPosition(const GeoPoint(51.507351, -0.127758)); // London
    s = await AppStore.load();
    expect(s.lastPosition!.lat, closeTo(51.50735, 1e-5));
    expect(s.lastPosition!.lng, closeTo(-0.12776, 1e-5));
  });

  test('a damaged saved position is ignored, not a crash', () async {
    SharedPreferences.setMockInitialValues({'seeded': true, 'lastPos': '{"lat": 999, "lng": 0}'});
    expect((await AppStore.load()).lastPosition, isNull);
    SharedPreferences.setMockInitialValues({'seeded': true, 'lastPos': 'nonsense'});
    expect((await AppStore.load()).lastPosition, isNull);
  });
}
