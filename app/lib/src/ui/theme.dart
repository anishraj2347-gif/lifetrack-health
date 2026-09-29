import 'package:flutter/material.dart';

/// Warm-grey clinical dashboard: black pills, large soft cards, one lime
/// accent. Poppins throughout, bundled.
///
/// **Lime means "selected / current" and nothing else** — never a health
/// status. It is measured against the semantic colours so it cannot be
/// mistaken for one (worst: vs caution fill ΔE 38.9 under deuteranopia).
///
/// Three semantic colours, CVD-checked (ΔE76, Machado 2009 simulation):
///
///   trace   #065F46  emerald-800 — stayed on device / live control
///   signal  #C2410C  orange-700  — outside the reference interval; allergies
///   caution #FEF3C7  amber-100   — could not check. Fill only, amber-900 text.
///
///   worst pair: trace–signal ΔE 34.3 under protanopia (deutan 53.1).
///   caution–signal ≥ 56.8 in every mode. White on signal 5.2:1 (AA).
///
/// Pure red (#DC2626) was rejected: under protanopia it darkens onto the green
/// (ΔE 11.6). The amber border #FDE68A was rejected next to lime (ΔE 14.4).
/// Re-run the measurement before changing any of these.
abstract final class LT {
  static const ground = Color(0xFFE3E3DC); // page
  static const surface = Color(0xFFF4F4EF); // light card
  static const raised = Color(0xFFFBFBF8); // pills, inputs, icon circles
  static const band = surface; // muted panels
  static const rule = Color(0xFFD4D3CC);
  static const ink = Color(0xFF0E0E0E);
  static const ink2 = Color(0xFF45443F);
  static const ink3 = Color(0xFF7F7E78);
  static const inactive = Color(0xFFA9A8A1);
  static const primary = Color(0xFF0E0E0E);
  static const onDark = Color(0xFFF4F4EF);
  static const onDarkMuted = Color(0xFF9A9A94);

  /// Selection / "now" only.
  static const accent = Color(0xFFEEF36A);

  static const trace = Color(0xFF065F46);
  static const signal = Color(0xFFC2410C);
  static const caution = Color(0xFFFEF3C7);
  static const cautionBorder = Color(0xFFE3C878);
  static const cautionInk = Color(0xFF78350F);

  static const radius = 16.0;
  static const radiusLg = 22.0;

  static const display = 'Poppins';
  static const body = 'Poppins';
  static const mono = 'Poppins';

  static const eyebrow = TextStyle(fontFamily: body, fontSize: 12.5, fontWeight: FontWeight.w500, color: ink3);
  static const title = TextStyle(fontFamily: display, fontSize: 26, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.6, color: ink);
  static const hero = TextStyle(fontFamily: display, fontSize: 30, fontWeight: FontWeight.w600, height: 1.12, letterSpacing: -0.8, color: ink);
  static const lede = TextStyle(fontFamily: body, fontSize: 14.5, height: 1.55, color: ink3);
  static const label = TextStyle(fontFamily: body, fontSize: 15, fontWeight: FontWeight.w500, color: ink, letterSpacing: -0.1);
  static const small = TextStyle(fontFamily: body, fontSize: 12.5, height: 1.5, color: ink3);
  static const data = TextStyle(fontFamily: mono, fontSize: 14.5, fontWeight: FontWeight.w600, color: ink, fontFeatures: [FontFeature.tabularFigures()]);

  static ThemeData theme() {
    const none = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(radius)), borderSide: BorderSide(color: raised));
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ground,
      fontFamily: body,
      splashFactory: NoSplash.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onDark,
        secondary: accent,
        onSecondary: ink,
        error: signal,
        surface: surface,
        onSurface: ink,
        outline: rule,
      ),
      dividerColor: rule,
      appBarTheme: const AppBarTheme(
        backgroundColor: ground,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: raised,
        hintStyle: TextStyle(color: inactive),
        border: none,
        enabledBorder: none,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: ink, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
        side: const BorderSide(color: primary, width: 1.3),
        checkColor: const WidgetStatePropertyAll(accent),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
      ),
      datePickerTheme: const DatePickerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primary,
        contentTextStyle: TextStyle(fontFamily: body, color: onDark),
        shape: StadiumBorder(),
      ),
    );
  }
}
