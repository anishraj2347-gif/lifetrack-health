import 'package:flutter/material.dart';

/// shadcn/ui "zinc" design tokens, implemented natively (the Flutter port of
/// shadcn pulls in network-capable packages — see CLAUDE.md #3).
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
/// (ΔE 11.6), making "on this phone" and "out of range" look alike. Re-run the
/// measurement before changing any of the three.
abstract final class LT {
  static const ground = Color(0xFFFFFFFF); // background
  static const band = Color(0xFFF4F4F5); // muted
  static const rule = Color(0xFFE4E4E7); // border
  static const ink = Color(0xFF09090B); // foreground
  static const ink2 = Color(0xFF52525B); // zinc-600
  static const ink3 = Color(0xFF71717A); // muted-foreground
  static const inactive = Color(0xFFA1A1AA); // zinc-400
  static const primary = Color(0xFF18181B); // zinc-900

  static const trace = Color(0xFF065F46);
  static const signal = Color(0xFFC2410C);
  static const caution = Color(0xFFFEF3C7);
  static const cautionBorder = Color(0xFFFDE68A);
  static const cautionInk = Color(0xFF78350F);

  static const radius = 8.0;
  static const radiusLg = 12.0;

  static const display = 'Geist';
  static const body = 'Geist';
  static const mono = 'Geist Mono';

  /// Small muted label above a title or section.
  static const eyebrow = TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w500, color: ink3);

  static const title = TextStyle(fontFamily: display, fontSize: 26, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.6, color: ink);

  static const hero = TextStyle(fontFamily: display, fontSize: 30, fontWeight: FontWeight.w600, height: 1.12, letterSpacing: -0.8, color: ink);

  static const lede = TextStyle(fontFamily: body, fontSize: 15, height: 1.55, color: ink3);
  static const label = TextStyle(fontFamily: body, fontSize: 15, fontWeight: FontWeight.w500, color: ink, letterSpacing: -0.1);
  static const small = TextStyle(fontFamily: body, fontSize: 13, height: 1.5, color: ink3);
  static const data = TextStyle(fontFamily: mono, fontSize: 14, fontWeight: FontWeight.w500, color: ink);

  static ThemeData theme() {
    const outline = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      borderSide: BorderSide(color: rule),
    );
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ground,
      fontFamily: body,
      splashFactory: NoSplash.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Color(0xFFFAFAFA),
        secondary: band,
        onSecondary: primary,
        error: signal,
        surface: ground,
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
        fillColor: ground,
        hintStyle: TextStyle(color: inactive),
        border: outline,
        enabledBorder: outline,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: ink2, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
        side: const BorderSide(color: primary, width: 1.2),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
      ),
      datePickerTheme: const DatePickerThemeData(backgroundColor: ground, surfaceTintColor: Colors.transparent),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}
