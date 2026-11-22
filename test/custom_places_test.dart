import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/config/app_build.dart';
import 'package:golicat/core/geo.dart';
import 'package:golicat/places/custom_place.dart';
import 'package:golicat/places/place_store.dart';
import 'package:golicat/tracking/place_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('appBuild matches pubspec.yaml', () {
    final v = RegExp(r'^version: .*\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(appBuild, int.parse(v.group(1)!));
  });

  test('custom places: add, edit, remove, Bangla names, survive a reload', () async {
    SharedPreferences.setMockInitialValues({'seeded': true});
    var s = await AppStore.load();
    await s.saveCustomPlace(CustomPlace(id: 'a', name: 'আম্মুর বাসা', icon: 'family', center: const GeoPoint(23.75, 90.39)));
    await s.saveCustomPlace(CustomPlace(id: 'b', name: 'Gym', icon: 'gym', center: const GeoPoint(23.76, 90.4)));
    await s.saveCustomPlace(s.customPlaces.first.copyWith(name: 'আম্মুর বাসা · Mum'));
    s = await AppStore.load();
    expect(s.customPlaces.map((c) => c.name), ['আম্মুর বাসা · Mum', 'Gym']);
    expect(s.customPlaces.first.look.key, 'family');
    await s.removeCustomPlace('b');
    expect(s.customPlaces.map((c) => c.id), ['a']);
  });

  test('a damaged entry or an unknown icon never loses the other places', () async {
    SharedPreferences.setMockInitialValues({
      'seeded': true,
      'customPlaces': jsonEncode([
        {'id': 'ok', 'name': 'Bazar', 'icon': 'bazar', 'lat': 23.7, 'lng': 90.4},
        {'id': 'bad', 'name': 'x'},
        {'id': 'new', 'name': 'Future', 'icon': 'rocket', 'lat': 23.7, 'lng': 90.4},
      ]),
    });
    final s = await AppStore.load();
    expect(s.customPlaces.map((c) => c.id), ['ok', 'new']);
    expect(s.customPlaces.last.look.key, 'pin');
  });

  test('update from 1.0.3 keeps every place and the avatar, and is noticed once', () async {
    final home = jsonEncode(Place(center: const GeoPoint(23.78, 90.41), radiusM: 60).toJson());
    SharedPreferences.setMockInitialValues({'seeded': true, 'place_home': home, 'catSkin': 'batcat', 'lastBuild': 12});
    final before = (await SharedPreferences.getInstance()).getString('place_home');
    var s = await AppStore.load();
    expect(s.updatedFrom, 12);
    expect(s.catSkinId, 'batcat');
    expect((await SharedPreferences.getInstance()).getString('place_home'), before);
    expect(s.place(PlaceKind.home)!.center.lat, 23.78);
    expect(s.customPlaces, isEmpty);
    s = await AppStore.load();
    expect(s.updatedFrom, isNull, reason: 'only the first start after the update');
  });

  test('update from a build before version tracking is noticed too', () async {
    SharedPreferences.setMockInitialValues({'seeded': true, 'catSkin': 'ginger'});
    final s = await AppStore.load();
    expect(s.updatedFrom, 0);
  });

  test('fresh install is not an update', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppStore.load();
    expect(s.updatedFrom, isNull);
  });
}
