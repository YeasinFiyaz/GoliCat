import 'package:material_ui/material_ui.dart';

import 'places/place_store.dart';
import 'ui/map_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.load();
  runApp(GoliCatApp(store: store));
}

class GoliCatApp extends StatelessWidget {
  const GoliCatApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoliCat',
      debugShowCheckedModeBanner: false,
      theme: GoliTheme.light(),
      home: MapScreen(store: store),
    );
  }
}
