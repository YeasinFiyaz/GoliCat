import 'package:material_ui/material_ui.dart';

import '../core/geo.dart';

/// A place the user pins with their own name and icon (a hospital, the
/// bazar, a friend's house…). Shown on the map; stored only on this phone.
class CustomPlace {
  CustomPlace({required this.id, required this.name, required this.icon, required this.center});

  /// Stable id, so editing never duplicates a pin.
  final String id;

  /// Whatever the user typed, Bangla or English.
  final String name;

  /// A key from [placeIcons]. Unknown keys (from a newer version) fall back.
  final String icon;
  final GeoPoint center;

  static const maxName = 30;
  static const maxCount = 50;

  PlaceIcon get look => placeIconOf(icon);

  CustomPlace copyWith({String? name, String? icon, GeoPoint? center}) =>
      CustomPlace(id: id, name: name ?? this.name, icon: icon ?? this.icon, center: center ?? this.center);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon, 'lat': center.lat, 'lng': center.lng};

  /// Null for anything malformed, so one bad entry never loses the rest.
  static CustomPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], lat = j['lat'], lng = j['lng'];
    if (id is! String || id.isEmpty || name is! String || lat is! num || lng is! num) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    final icon = j['icon'];
    return CustomPlace(
      id: id,
      name: name.trim().isEmpty ? 'My place' : name.trim(),
      icon: icon is String ? icon : 'pin',
      center: GeoPoint(lat.toDouble(), lng.toDouble()),
    );
  }
}

/// One suggested icon with a ready-made bilingual name.
class PlaceIcon {
  const PlaceIcon(this.key, this.icon, this.color, this.bn, this.en);
  final String key;
  final IconData icon;
  final Color color;
  final String bn, en;
  String get suggestedName => '$bn · $en';
}

/// The icons offered under "More". Keys are stored in preferences: never
/// rename or remove one, only add.
const placeIcons = <PlaceIcon>[
  PlaceIcon('home', Icons.home, Color(0xFF2F5D8A), 'বাসা', 'Home'),
  PlaceIcon('shop', Icons.shopping_bag, Color(0xFFD9822B), 'শপিং', 'Shopping'),
  PlaceIcon('bazar', Icons.storefront, Color(0xFF8A5A2B), 'বাজার', 'Bazar'),
  PlaceIcon('hospital', Icons.local_hospital, Color(0xFFD7263D), 'হাসপাতাল', 'Hospital'),
  PlaceIcon('pharmacy', Icons.local_pharmacy, Color(0xFF2E9E8F), 'ফার্মেসি', 'Pharmacy'),
  PlaceIcon('school', Icons.school, Color(0xFF2F8F6B), 'স্কুল', 'School'),
  PlaceIcon('work', Icons.work, Color(0xFF5B5F97), 'কাজ', 'Work'),
  PlaceIcon('food', Icons.restaurant, Color(0xFFE4572E), 'রেস্টুরেন্ট', 'Restaurant'),
  PlaceIcon('tea', Icons.local_cafe, Color(0xFF7A4E2D), 'চায়ের দোকান', 'Tea stall'),
  PlaceIcon('mosque', Icons.mosque, Color(0xFF1F7A5A), 'মসজিদ', 'Mosque'),
  PlaceIcon('temple', Icons.temple_hindu, Color(0xFFE08A1E), 'মন্দির', 'Temple'),
  PlaceIcon('church', Icons.church, Color(0xFF6E6A9E), 'গির্জা', 'Church'),
  PlaceIcon('gym', Icons.fitness_center, Color(0xFF3B3B58), 'জিম', 'Gym'),
  PlaceIcon('park', Icons.park, Color(0xFF3A9D4A), 'পার্ক', 'Park'),
  PlaceIcon('bus', Icons.directions_bus, Color(0xFF1C77C3), 'বাস স্ট্যান্ড', 'Bus stop'),
  PlaceIcon('train', Icons.train, Color(0xFF4A4E69), 'স্টেশন', 'Station'),
  PlaceIcon('bank', Icons.account_balance, Color(0xFF2B6F8A), 'ব্যাংক', 'Bank'),
  PlaceIcon('fuel', Icons.local_gas_station, Color(0xFFB23A48), 'পাম্প', 'Fuel'),
  PlaceIcon('salon', Icons.content_cut, Color(0xFFC0508A), 'সেলুন', 'Salon'),
  PlaceIcon('friends', Icons.people, Color(0xFF6C63FF), 'বন্ধুর বাসা', "Friend's place"),
  PlaceIcon('family', Icons.family_restroom, Color(0xFF9C4F96), 'আত্মীয়ের বাসা', 'Family'),
  PlaceIcon('love', Icons.favorite, Color(0xFFE5446D), 'প্রিয় জায়গা', 'Favourite'),
  PlaceIcon('pin', Icons.place, Color(0xFF555B6E), 'অন্যান্য', 'Other'),
];

/// What GoliCat does after a minute at a pin with this icon (for the editor).
String catActivityFor(String key) => switch (key) {
      'home' => 'GoliCat goes about its home day: bath, food, phone, games, naps',
      'work' => 'GoliCat clocks in at its desk',
      'school' => 'GoliCat puts on its glasses and does homework',
      'tea' => 'GoliCat sits down for a cha break',
      'friends' || 'family' => 'GoliCat puts on headphones and hangs out',
      'bazar' => 'GoliCat haggles for a fish: কত? না না!',
      'food' => 'GoliCat tucks in a napkin and eats biryani',
      'bus' => "GoliCat waits for the bus… which doesn't stop",
      'park' => 'GoliCat chases a butterfly and sunbathes',
      'mosque' || 'temple' || 'church' => 'Just a pin on your map',
      _ => 'Just a pin on your map for now',
    };

PlaceIcon placeIconOf(String key) => placeIcons.firstWhere((i) => i.key == key, orElse: () => placeIcons.last);
