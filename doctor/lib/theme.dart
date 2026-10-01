import 'package:flutter/material.dart';

/// Follow device, light or dark — the doctor's choice (My code → Appearance).
final appearance = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode themeModeOf(String? choice) => switch (choice) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

/// Same warm-grey language as the patient app, laid out for a clinic desktop,
/// with the same dark palette (see the patient app's theme for the measured
/// semantic colours).
abstract final class DT {
  static bool dark = false;
  static Color _p(int light, int darkValue) => Color(dark ? darkValue : light);

  static Color get ground => _p(0xFFE3E3DC, 0xFF121210);
  static Color get surface => _p(0xFFF4F4EF, 0xFF1D1D1A);
  static Color get raised => _p(0xFFFBFBF8, 0xFF272724);
  static Color get ink => _p(0xFF0E0E0E, 0xFFF2F2EC);
  static Color get ink3 => _p(0xFF64635D, 0xFFA6A59E); // ≥ 4.5:1 on ground and cards (contrast_test)

  /// Dark hero cards (black in light mode, lifted in dark).
  static Color get hero => _p(0xFF0E0E0E, 0xFF2E2E2A);
  static Color get onDark => _p(0xFFF4F4EF, 0xFFF2F2EC);
  static Color get onDarkMuted => _p(0xFF9A9A94, 0xFFA6A59E);

  /// Primary buttons and selected choices: black on light, cream on dark.
  static Color get button => _p(0xFF0E0E0E, 0xFFF2F2EC);
  static Color get onButton => _p(0xFFF4F4EF, 0xFF121210);

  static const accent = Color(0xFFEEF36A);
  static const onAccent = Color(0xFF0E0E0E);
  static Color get signal => _p(0xFFC2410C, 0xFFF97316);
  static Color get trace => _p(0xFF065F46, 0xFF10B981);
  static const signalFill = Color(0xFFC2410C);
  static const caution = Color(0xFFFEF3C7);
  static const cautionInk = Color(0xFF78350F);

  static TextStyle get h1 => TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: ink);
  static TextStyle get h2 => TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: ink);
  static TextStyle get body => TextStyle(fontFamily: 'Poppins', fontSize: 14, color: ink, height: 1.5);
  static TextStyle get muted => TextStyle(fontFamily: 'Poppins', fontSize: 13, color: ink3, height: 1.5);
  static TextStyle get label => TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: ink);

  static ThemeData theme() {
    final b = dark ? Brightness.dark : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF0E0E0E), brightness: b).copyWith(
        primary: button,
        onPrimary: onButton,
        secondary: accent,
        onSecondary: onAccent,
        secondaryContainer: accent,
        onSecondaryContainer: onAccent,
        surface: surface,
        onSurface: ink,
        error: signal,
      ),
      textTheme: ThemeData(brightness: b).textTheme.apply(fontFamily: 'Poppins', bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: ink),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      popupMenuTheme: PopupMenuThemeData(color: raised, textStyle: TextStyle(fontFamily: 'Poppins', color: ink)),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: raised, indicatorColor: accent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        isDense: true,
        hintStyle: TextStyle(color: ink3),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class Card0 extends StatelessWidget {
  const Card0({super.key, required this.child, this.dark = false, this.onTap});
  final Widget child;
  final bool dark;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Material(
      color: dark ? DT.hero : DT.raised,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(padding: EdgeInsets.all(18), child: child),
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.onTap, this.dark = true});
  final String label;
  final VoidCallback? onTap;
  final bool dark;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Material(
      color: onTap == null ? DT.ink3 : (dark ? DT.button : DT.raised),
      shape: StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: dark ? DT.onButton : DT.ink),
          ),
        ),
      ),
    ),
  );
}

class Field extends StatelessWidget {
  const Field(this.label, this.controller, {super.key, this.hint, this.maxLines = 1});
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DT.label),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: 1,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint == null ? null : 'e.g. $hint', hintStyle: TextStyle(color: DT.ink3)),
        ),
      ],
    ),
  );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 3 Oct 2026
String fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// 3 Oct 2026, 14:05
String fmtDateTime(DateTime d) {
  final l = d.toLocal();
  return '${fmtDate(l)}, ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// 1482 0937 5516
String fmtLifeTrackId(String id) => id.length == 12 ? '${id.substring(0, 4)} ${id.substring(4, 8)} ${id.substring(8)}' : id;

/// A small status label.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this._color, this._ink});
  final String text;
  final Color? _color;
  final Color? _ink;
  Color get color => _color ?? DT.surface;
  Color get ink => _ink ?? DT.ink;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: ShapeDecoration(color: color, shape: StadiumBorder()),
        child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
      );
}
