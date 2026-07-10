import 'package:flutter/material.dart';
import 'tokens.dart';

/// Vaikus — "stillness". Calm Nordic-minimal default (spec §8.4).
const vaikus = RadaTokens(
  name: 'Vaikus',
  brightness: Brightness.light,
  surface: Color(0xFFFAF8F5), // warm off-white
  surfaceAlt: Color(0xFFF0EDE8),
  textPrimary: Color(0xFF23282B),
  textSecondary: Color(0xFF6B7378),
  accent: Color(0xFF2E7D74), // muted teal
  accentAlt: Color(0xFF2E7D74),
  success: Color(0xFF3E8E5A),
  warning: Color(0xFFC98A2B),
);

/// Vaikus, dark variant.
const vaikusDark = RadaTokens(
  name: 'Vaikus (tume)',
  brightness: Brightness.dark,
  surface: Color(0xFF1D2124), // deep charcoal
  surfaceAlt: Color(0xFF272C30),
  textPrimary: Color(0xFFECEAE6),
  textSecondary: Color(0xFF9AA3A8),
  accent: Color(0xFF5BA79D),
  accentAlt: Color(0xFF5BA79D),
  success: Color(0xFF63B283),
  warning: Color(0xFFD9A050),
);

/// Põhjavalgus — "northern lights". Dark-native, aurora accents (spec §8.4).
const pohjavalgus = RadaTokens(
  name: 'Põhjavalgus',
  brightness: Brightness.dark,
  surface: Color(0xFF0C1116), // near-black night sky
  surfaceAlt: Color(0xFF141C24),
  textPrimary: Color(0xFFF2F5F7),
  textSecondary: Color(0xFF8FA0AD),
  accent: Color(0xFF35E0A1), // aurora green
  accentAlt: Color(0xFF8A6CF0), // aurora violet (gradient stop)
  success: Color(0xFF35E0A1),
  warning: Color(0xFFF0B95C),
  motion: Duration(milliseconds: 300), // slightly livelier
);

const allThemes = [vaikus, vaikusDark, pohjavalgus];
