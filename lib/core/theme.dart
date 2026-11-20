import 'package:material_ui/material_ui.dart';

import '../domain/enums.dart';

class AppColors {
  static const black = Color(0xFF0A0A0B);
  static const graphite = Color(0xFF16171A);
  static const graphite2 = Color(0xFF202227);
  static const outline = Color(0xFF34363D);
  static const gold = Color(0xFFD4AF37);
  static const goldSoft = Color(0xFFE9D48A);
  static const white = Color(0xFFF4F4F5);
  static const muted = Color(0xFF9A9CA5);
  static const pass = Color(0xFF3FB984);
  static const watch = Color(0xFFE5A93B);
  static const fail = Color(0xFFE5534B);
  static const unknown = Color(0xFF7D8590);

  static Color verdict(FinalVerdict? v) => switch (v) {
        FinalVerdict.approved => pass,
        FinalVerdict.watch => watch,
        FinalVerdict.rejected => fail,
        FinalVerdict.incomplete => unknown,
        null => outline,
      };

  static Color outcome(VisaOutcome o) => switch (o) {
        VisaOutcome.pass => pass,
        VisaOutcome.watch => watch,
        VisaOutcome.fail => fail,
        VisaOutcome.unknown => unknown,
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.gold,
    onPrimary: AppColors.black,
    secondary: AppColors.goldSoft,
    surface: AppColors.graphite,
    onSurface: AppColors.white,
    surfaceContainerHighest: AppColors.graphite2,
    outline: AppColors.outline,
    error: AppColors.fail,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.white,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
          color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.2),
    ),
    cardTheme: CardThemeData(
      color: AppColors.graphite,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.outline, width: 0.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.graphite,
      indicatorColor: AppColors.gold.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, color: AppColors.white)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.graphite2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 0.6),
    chipTheme: const ChipThemeData(backgroundColor: AppColors.graphite2),
  );
}
