import 'package:flutter/material.dart';

/// Same warm-grey language as the patient app, laid out for a clinic desktop.
abstract final class DT {
  static const ground = Color(0xFFE3E3DC);
  static const surface = Color(0xFFF4F4EF);
  static const raised = Color(0xFFFBFBF8);
  static const ink = Color(0xFF0E0E0E);
  static const ink3 = Color(0xFF64635D); // 4.7:1 on ground (contrast_test)
  static const onDark = Color(0xFFF4F4EF);
  static const onDarkMuted = Color(0xFF9A9A94);
  static const accent = Color(0xFFEEF36A);
  static const signal = Color(0xFFC2410C);
  static const trace = Color(0xFF065F46);
  static const caution = Color(0xFFFEF3C7);
  static const cautionInk = Color(0xFF78350F);

  static const h1 = TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: ink);
  static const h2 = TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: ink);
  static const body = TextStyle(fontFamily: 'Poppins', fontSize: 14, color: ink, height: 1.5);
  static const muted = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: ink3, height: 1.5);
  static const label = TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: ink);

  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: surface,
    colorScheme: const ColorScheme.light(primary: ink, secondary: accent, surface: surface, error: signal),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: raised,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class Card0 extends StatelessWidget {
  const Card0({super.key, required this.child, this.dark = false, this.onTap});
  final Widget child;
  final bool dark;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: dark ? DT.ink : DT.raised,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
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
      color: onTap == null ? DT.ink3 : (dark ? DT.ink : DT.raised),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: dark ? DT.onDark : DT.ink),
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
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DT.label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: 1,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint == null ? null : 'e.g. $hint', hintStyle: const TextStyle(color: DT.ink3)),
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
  const Tag(this.text, {super.key, this.color = DT.surface, this.ink = DT.ink});
  final String text;
  final Color color;
  final Color ink;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
        child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
      );
}
