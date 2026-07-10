/// UI language modes (spec §8.4 amendment):
/// - 'en'   — English only (clarity first)
/// - 'both' — English · Estonian (default: passive vocabulary exposure)
/// - 'et'   — Estonian only (graduation mode)
class L10n {
  final String mode;
  const L10n(this.mode);

  String t(String en, String et) {
    switch (mode) {
      case 'et':
        return et;
      case 'both':
        return '$en · $et';
      default:
        return en;
    }
  }

  /// For tight spaces (chips, buttons): both-mode shows English with the
  /// Estonian in brackets only if short enough.
  String short(String en, String et) {
    switch (mode) {
      case 'et':
        return et;
      case 'both':
        return et.length <= 12 ? '$en ($et)' : en;
      default:
        return en;
    }
  }

  static const modes = ['en', 'both', 'et'];
  static String modeLabel(String m) {
    switch (m) {
      case 'et':
        return 'Eesti keeles';
      case 'both':
        return 'English · Eesti';
      default:
        return 'English';
    }
  }
}
