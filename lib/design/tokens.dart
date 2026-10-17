import 'package:flutter/material.dart';

/// Design tokens for NOVA CRAFT.
///
/// The visual language is a deep navy "night sky" with electric blue, indigo
/// and violet light. Everything in the app reads from these tokens so screens
/// stay consistent instead of inventing their own colors and spacing.
class NovaPalette {
  const NovaPalette({
    required this.brightness,
    required this.bg,
    required this.bgDeep,
    required this.surface,
    required this.card,
    required this.cardSoft,
    required this.cardHigh,
    required this.stroke,
    required this.strokeStrong,
    required this.overlay,
    required this.primary,
    required this.primaryBright,
    required this.indigo,
    required this.violet,
    required this.cyan,
    required this.success,
    required this.successBright,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.onPrimary,
  });

  final Brightness brightness;
  final Color bg;
  final Color bgDeep;
  final Color surface;
  final Color card;
  final Color cardSoft;
  final Color cardHigh;
  final Color stroke;
  final Color strokeStrong;
  final Color overlay;
  final Color primary;
  final Color primaryBright;
  final Color indigo;
  final Color violet;
  final Color cyan;
  final Color success;
  final Color successBright;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color text;
  final Color textMuted;
  final Color textDim;
  final Color onPrimary;

  bool get isDark => brightness == Brightness.dark;

  static const NovaPalette dark = NovaPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF070B18),
    bgDeep: Color(0xFF04060E),
    surface: Color(0xFF0C132A),
    card: Color(0xFF141D3A),
    cardSoft: Color(0xFF101830),
    cardHigh: Color(0xFF1B2649),
    stroke: Color(0x14FFFFFF),
    strokeStrong: Color(0x4D6E7BFF),
    overlay: Color(0x9904060E),
    primary: Color(0xFF3B82F6),
    primaryBright: Color(0xFF5B9CFF),
    indigo: Color(0xFF4F5BFF),
    violet: Color(0xFFA855F7),
    cyan: Color(0xFF22D3EE),
    success: Color(0xFF22C55E),
    successBright: Color(0xFF34D399),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    dangerSoft: Color(0xFFF87171),
    text: Color(0xFFEDF2FF),
    textMuted: Color(0xFF9AA9C9),
    textDim: Color(0xFF64739A),
    onPrimary: Colors.white,
  );

  static const NovaPalette light = NovaPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF2F5FC),
    bgDeep: Color(0xFFE7EDF9),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardSoft: Color(0xFFF6F8FE),
    cardHigh: Color(0xFFEDF2FF),
    stroke: Color(0x140B1530),
    strokeStrong: Color(0x334F46E5),
    overlay: Color(0xCCFFFFFF),
    primary: Color(0xFF2563EB),
    primaryBright: Color(0xFF3B82F6),
    indigo: Color(0xFF4F46E5),
    violet: Color(0xFF7C3AED),
    cyan: Color(0xFF0891B2),
    success: Color(0xFF16A34A),
    successBright: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFEF4444),
    text: Color(0xFF0B1430),
    textMuted: Color(0xFF5A6685),
    textDim: Color(0xFF8792AD),
    onPrimary: Colors.white,
  );

  Color soft(Color c, double alpha) => c.withValues(alpha: alpha);
}

class NovaSpace {
  const NovaSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double giant = 56;

  /// Standard horizontal page padding.
  static const double page = 20;
}

class NovaRadii {
  const NovaRadii._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

class NovaGradients {
  const NovaGradients._();

  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF4F8DFF), Color(0xFF4F5BFF), Color(0xFF6D4AFF)],
  );

  static const LinearGradient primaryDiagonal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF4F8DFF), Color(0xFF3B6BF6)],
  );

  static const LinearGradient violet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF7C4DFF), Color(0xFFA855F7)],
  );

  static const LinearGradient danger = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFF2555A), Color(0xFFDC2F3C)],
  );

  static const LinearGradient success = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF2FD07B), Color(0xFF16A34A)],
  );

  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFFFD36E), Color(0xFFF59E0B)],
  );

  static LinearGradient card(NovaPalette p) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: p.isDark
            ? <Color>[Color(0xFF18223F), Color(0xFF101830)]
            : <Color>[Colors.white, Color(0xFFF5F8FF)],
      );

  static LinearGradient cardGlow(NovaPalette p, Color accent) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color.alphaBlend(accent.withValues(alpha: p.isDark ? 0.18 : 0.10), p.card),
          p.cardSoft,
        ],
      );

  static LinearGradient fade(NovaPalette p) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Colors.transparent, p.bg.withValues(alpha: 0.85), p.bg],
        stops: const <double>[0.0, 0.72, 1.0],
      );

  static const LinearGradient heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x1A05070F), Color(0x66070B18), Color(0xF2070B18)],
    stops: <double>[0.0, 0.55, 1.0],
  );

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF7FE3FF), Color(0xFF5B9CFF), Color(0xFF7C4DFF)],
  );
}

class NovaShadows {
  const NovaShadows._();

  static List<BoxShadow> soft(NovaPalette p) => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.06),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> lifted(NovaPalette p) => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.10),
          blurRadius: 34,
          offset: const Offset(0, 18),
        ),
      ];

  static List<BoxShadow> glow(Color color, {double alpha = 0.45, double blur = 26, double y = 10}) => <BoxShadow>[
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: blur,
          offset: Offset(0, y),
        ),
      ];
}

class NovaDurations {
  const NovaDurations._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration breathe = Duration(milliseconds: 2200);
}

class NovaTextStyles {
  const NovaTextStyles._();

  static const List<String> fallback = <String>['Cairo'];

  static TextStyle _base(
    double size,
    FontWeight weight, {
    String family = 'Manrope',
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static TextStyle display(double size, Color color) =>
      _base(size, FontWeight.w800, family: 'Oxanium', height: 1.08, letterSpacing: -0.2, color: color);

  static TextStyle brand(double size, Color color) =>
      _base(size, FontWeight.w700, family: 'Oxanium', height: 1.0, letterSpacing: 2.4, color: color);

  static TextStyle heading(double size, Color color) =>
      _base(size, FontWeight.w700, family: 'Oxanium', height: 1.18, letterSpacing: 0.1, color: color);

  static TextStyle title(Color color) => _base(16, FontWeight.w700, height: 1.3, color: color);

  static TextStyle body(Color color) => _base(14.5, FontWeight.w500, height: 1.5, color: color);

  static TextStyle bodyStrong(Color color) => _base(14.5, FontWeight.w700, height: 1.45, color: color);

  static TextStyle small(Color color) => _base(12.5, FontWeight.w500, height: 1.45, color: color);

  static TextStyle smallStrong(Color color) => _base(12.5, FontWeight.w700, height: 1.4, color: color);

  static TextStyle caption(Color color) =>
      _base(10.5, FontWeight.w700, height: 1.2, letterSpacing: 1.1, color: color);

  static TextStyle button(Color color) => _base(15, FontWeight.w700, height: 1.2, letterSpacing: 0.2, color: color);

  static TextStyle mono(double size, Color color) =>
      _base(size, FontWeight.w400, family: 'PlexMono', height: 1.5, color: color);

  static TextStyle monoStrong(double size, Color color) =>
      _base(size, FontWeight.w600, family: 'PlexMono', height: 1.5, color: color);

  static TextStyle number(double size, Color color) =>
      _base(size, FontWeight.w700, family: 'Oxanium', height: 1.0, letterSpacing: 0.2, color: color);
}
