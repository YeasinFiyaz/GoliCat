import 'package:material_ui/material_ui.dart';

class GoliTheme {
  static const red = Color(0xFFD7263D);
  static const ink = Color(0xFF2E221B);
  static const paper = Color(0xFFFBF6EE);

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(seedColor: red, brightness: Brightness.light).copyWith(
      primary: red,
      onPrimary: Colors.white,
      surface: paper,
      onSurface: ink,
    );
    return ThemeData(
      colorScheme: cs,
      scaffoldBackgroundColor: paper,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        showDragHandle: true,
      ),
    );
  }
}
