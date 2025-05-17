// lib/theme/app_themes.dart

import 'package:flutter/material.dart';

// --- Global Theme Notifiers ---
final ValueNotifier<ThemeMode> currentThemeMode =
    ValueNotifier(ThemeMode.light);
final ValueNotifier<Color> currentSeedColor =
    ValueNotifier(AppThemes.colorOptions[0].color ?? Colors.blueAccent);
final ValueNotifier<bool> isHighContrastMode = ValueNotifier(false);
final ValueNotifier<bool> isHighContrastDark = ValueNotifier(false);

enum ThemeSetting {
  oceanBlue,
  forestGreen,
  sunsetOrange,
  royalPurple,
  crimsonRed,
  system,
  lightMode,
  darkMode,
  highContrastLight,
  highContrastDark
}

class AppThemeOption {
  final String name;
  final Color? color; // Null for mode options
  final ThemeSetting setting;

  AppThemeOption(this.name, this.setting, {this.color});
}

class AppThemes {
  static final List<AppThemeOption> colorOptions = [
    AppThemeOption("Ocean Blue", ThemeSetting.oceanBlue,
        color: Colors.blue.shade300),
    AppThemeOption("Forest Green", ThemeSetting.forestGreen,
        color: Colors.green.shade300),
    AppThemeOption("Sunset Orange", ThemeSetting.sunsetOrange,
        color: Colors.orange.shade300),
    AppThemeOption("Royal Purple", ThemeSetting.royalPurple,
        color: Colors.purple.shade300),
    AppThemeOption("Crimson Red", ThemeSetting.crimsonRed,
        color: Colors.red.shade300),
  ];

  static final List<AppThemeOption> modeOptions = [
    AppThemeOption("System Default", ThemeSetting.system),
    AppThemeOption("Light Mode", ThemeSetting.lightMode),
    AppThemeOption("Dark Mode", ThemeSetting.darkMode),
    AppThemeOption("High Contrast Light", ThemeSetting.highContrastLight),
    AppThemeOption("High Contrast Dark", ThemeSetting.highContrastDark),
  ];

  static List<AppThemeOption> getAllThemeSettings() =>
      [...colorOptions, ...modeOptions];

  static ThemeData getThemeData(Color seedColor, Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurfaceVariant),
      dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme:
              InputDecorationTheme(fillColor: colorScheme.surfaceContainer)),
      dialogBackgroundColor: colorScheme.surfaceContainerHigh,
      // Add other common theme properties if needed
    );
  }

  static ThemeData get highContrastLightTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.highContrastLight(),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[200],
          foregroundColor: Colors.black,
          elevation: 1),
      textTheme:
          base.textTheme.apply(bodyColor: Colors.black, displayColor: Colors.black),
      iconTheme: const IconThemeData(color: Colors.black),
      // ... other high contrast light properties
    );
  }

  static ThemeData get highContrastDarkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.highContrastDark(),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          elevation: 1),
      textTheme:
          base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      // ... other high contrast dark properties
    );
  }
}