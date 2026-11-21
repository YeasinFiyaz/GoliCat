import 'package:material_ui/material_ui.dart';

import 'ui/theme.dart';
import 'viewer/viewer_screen.dart';

/// Web entry point for live-share links: `https://RELAY/s/SHARE_ID`.
/// Build: flutter build web -t lib/viewer_main.dart
void main() {
  final seg = Uri.base.pathSegments;
  final i = seg.indexOf('s');
  final id = i >= 0 && i + 1 < seg.length && RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(seg[i + 1]) ? seg[i + 1] : null;
  runApp(MaterialApp(
    title: 'GoliCat · live',
    debugShowCheckedModeBanner: false,
    theme: GoliTheme.light(),
    home: ViewerScreen(shareId: id, api: Uri.base.resolve('/api/s/')),
  ));
}
