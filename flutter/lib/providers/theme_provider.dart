import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme preference
enum ThemePreference { light, dark, system }

/// Theme provider for app-wide theme management
class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_preference';

  ThemePreference _themePreference = ThemePreference.system;

  ThemeProvider() {
    _loadPreferences();
  }

  ThemePreference get themePreference => _themePreference;

  ThemeMode get themeMode {
    switch (_themePreference) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
        return ThemeMode.system;
    }
  }

  // Tokens copied from `entry/src/main/ets/common/appTheme.ets` (LIGHT_THEME / DARK_THEME).
  static const int _lightPageBackground = 0xFFF3F4F6;
  static const int _lightSurface = 0xFFFFFFFF;
  static const int _lightSurfaceMuted = 0xFFF9FAFB;
  static const int _lightBorder = 0xFFE5E7EB;
  static const int _lightTitle = 0xFF1F2937;
  static const int _lightText = 0xFF374151;
  static const int _lightMutedText = 0xFF6B7280;
  static const int _lightDanger = 0xFFDC2626;
  static const int _lightAccent = 0xFF10B981;
  static const int _lightAccentOn = 0xFFFFFFFF;

  static const int _darkPageBackground = 0xFF0D1117;
  static const int _darkSurface = 0xFF161B22;
  static const int _darkSurfaceMuted = 0xFF21262D;
  static const int _darkBorder = 0xFF30363D;
  static const int _darkTitle = 0xFFF0F6FC;
  static const int _darkText = 0xFFC9D1D9;
  static const int _darkMutedText = 0xFF8B949E;
  static const int _darkDanger = 0xFFF85149;
  static const int _darkAccent = 0xFF58A6FF;
  static const int _darkAccentOn = 0xFF0D1117;

  /// Light theme data
  ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightColorScheme(),
    scaffoldBackgroundColor: const Color(_lightPageBackground),
    appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 1),
    dividerTheme: const DividerThemeData(color: Color(_lightBorder)),
    cardTheme: CardThemeData(
      color: const Color(_lightSurface),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(_lightBorder)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: Color(_lightTitle)),
      titleMedium: TextStyle(color: Color(_lightTitle)),
      titleSmall: TextStyle(color: Color(_lightTitle)),
      bodyLarge: TextStyle(color: Color(_lightText)),
      bodyMedium: TextStyle(color: Color(_lightText)),
      bodySmall: TextStyle(color: Color(_lightMutedText)),
    ),
  );

  /// Dark theme data
  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme(),
    scaffoldBackgroundColor: const Color(_darkPageBackground),
    appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 1),
    dividerTheme: const DividerThemeData(color: Color(_darkBorder)),
    cardTheme: CardThemeData(
      color: const Color(_darkSurface),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(_darkBorder)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: Color(_darkTitle)),
      titleMedium: TextStyle(color: Color(_darkTitle)),
      titleSmall: TextStyle(color: Color(_darkTitle)),
      bodyLarge: TextStyle(color: Color(_darkText)),
      bodyMedium: TextStyle(color: Color(_darkText)),
      bodySmall: TextStyle(color: Color(_darkMutedText)),
    ),
  );

  static ColorScheme _lightColorScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(_lightAccent),
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: const Color(_lightAccent),
      onPrimary: const Color(_lightAccentOn),
      surface: const Color(_lightSurface),
      onSurface: const Color(_lightText),
      surfaceContainerHighest: const Color(_lightSurfaceMuted),
      outline: const Color(_lightBorder),
      error: const Color(_lightDanger),
    );
  }

  static ColorScheme _darkColorScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(_darkAccent),
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: const Color(_darkAccent),
      onPrimary: const Color(_darkAccentOn),
      surface: const Color(_darkSurface),
      onSurface: const Color(_darkText),
      surfaceContainerHighest: const Color(_darkSurfaceMuted),
      outline: const Color(_darkBorder),
      error: const Color(_darkDanger),
    );
  }

  /// Load preferences from storage
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    final themeValue = prefs.getString(_themeKey);
    if (themeValue != null) {
      _themePreference = ThemePreference.values.firstWhere(
        (e) => e.name == themeValue,
        orElse: () => ThemePreference.system,
      );
    }

    notifyListeners();
  }

  /// Set theme preference
  Future<void> setThemePreference(ThemePreference preference) async {
    if (_themePreference == preference) return;
    
    _themePreference = preference;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, preference.name);
  }
}
