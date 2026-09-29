import 'package:flutter/material.dart';

/// "Measured": the record as a live instrument reading. Motif: the trace — a
/// hairline ending in a filled square marking "now".
///
/// Three semantic colours and no others. The palette is constrained by a
/// colour-vision-deficiency check (ΔE76 under simulated deuteranopia):
///   trace  vs signal   — passes only because trace is dark; L* carries it.
///                        Do not lighten trace without re-measuring.
///   caution vs signal  — caution is a pale fill with ink text. The earlier
///                        dark ochre #8A6114 measured ΔE 6.9 against signal,
///                        making "could not check" look like "out of range".
abstract final class LT {
  static const ground = Color(0xFFF1F3EF);
  static const band = Color(0xFFE4E8E1);
  static const rule = Color(0xFFD3D8D1);
  static const ink = Color(0xFF14181A);
  static const ink2 = Color(0xFF4A544F);
  static const ink3 = Color(0xFF7C867F);
  static const inactive = Color(0xFFA3ABA2);

  /// Stayed on this device / live control.
  static const trace = Color(0xFF1B4D3E);

  /// A value outside its reference interval; the Emergency ID allergy block.
  static const signal = Color(0xFFC2512B);

  /// Could not check / not yet verified. Fill only, with ink text.
  static const caution = Color(0xFFE8D5A3);

  static const display = 'Bricolage Grotesque';
  static const body = 'Public Sans';
  static const mono = 'Spline Sans Mono';

  static const eyebrow = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: ink3,
  );

  static const title = TextStyle(
    fontFamily: display,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.04,
    letterSpacing: -0.7,
    color: ink,
  );

  static const lede = TextStyle(fontFamily: body, fontSize: 15, height: 1.5, color: ink2);
  static const label = TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w600, color: ink);
  static const small = TextStyle(fontFamily: body, fontSize: 13, height: 1.45, color: ink2);
  static const data = TextStyle(fontFamily: mono, fontSize: 15, fontWeight: FontWeight.w600, color: ink);

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: ground,
        fontFamily: body,
        colorScheme: const ColorScheme.light(
          primary: ink,
          onPrimary: Colors.white,
          secondary: trace,
          error: signal,
          surface: ground,
          onSurface: ink,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: ink, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: ink, width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: trace, width: 2)),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        checkboxTheme: CheckboxThemeData(
          shape: const RoundedRectangleBorder(),
          fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ink : Colors.transparent),
        ),
      );
}
