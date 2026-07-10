import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rada/theme/themes.dart';

void main() {
  test('all themes produce valid ThemeData', () {
    for (final t in allThemes) {
      final theme = t.toThemeData();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, t.brightness);
    }
  });

  test('Põhjavalgus is dark-native with distinct gradient stops', () {
    expect(pohjavalgus.brightness, Brightness.dark);
    expect(pohjavalgus.accent, isNot(equals(pohjavalgus.accentAlt)));
  });
}
