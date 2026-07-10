import 'package:flutter/material.dart';

/// Design tokens (spec §8.4). Themes are token sets; components read tokens,
/// never raw colors. Adding a theme = adding one [RadaTokens] instance.
class RadaTokens {
  final String name;
  final Brightness brightness;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentAlt; // second gradient stop (aurora themes)
  final Color success;
  final Color warning;
  final double radius;
  final Duration motion;

  const RadaTokens({
    required this.name,
    required this.brightness,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentAlt,
    required this.success,
    required this.warning,
    this.radius = 14,
    this.motion = const Duration(milliseconds: 220),
  });

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(
        color: surfaceAlt,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      textTheme: Typography.material2021(platform: TargetPlatform.macOS)
          .black
          .apply(bodyColor: textPrimary, displayColor: textPrimary),
    );
  }
}
