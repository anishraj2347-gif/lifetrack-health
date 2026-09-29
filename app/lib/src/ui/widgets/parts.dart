import 'package:flutter/material.dart';

import '../theme.dart';

/// Screen header: eyebrow, display title, and the trace rule beneath.
class Masthead extends StatelessWidget {
  const Masthead({super.key, required this.eyebrow, required this.title, this.trailing});
  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.ink, width: 2))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(eyebrow.toUpperCase(), style: LT.eyebrow),
                      const SizedBox(height: 6),
                      Text(title, style: LT.title),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Trace(),
        ],
      );
}

/// The motif: a hairline ending in a filled square — "now".
class Trace extends StatelessWidget {
  const Trace({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 9,
        child: Stack(
          children: [
            const Positioned(left: 0, right: 0, top: 4, child: ColoredBox(color: LT.rule, child: SizedBox(height: 1))),
            Positioned(right: 20, top: 2, child: Container(width: 5, height: 5, color: LT.trace)),
          ],
        ),
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 8)});
  final String text;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: Text(text.toUpperCase(), style: LT.eyebrow));
}

/// Primary action: ink slab with the trace scanlines.
class SlabButton extends StatelessWidget {
  const SlabButton(this.label, {super.key, required this.onPressed, this.outline = false, this.color = LT.ink});
  final String label;
  final VoidCallback? onPressed;
  final bool outline;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outline ? null : (enabled ? color : LT.rule),
            border: outline ? Border.all(color: enabled ? color : LT.rule, width: 2) : null,
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: LT.mono,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: outline ? (enabled ? color : LT.ink3) : (enabled ? Colors.white : LT.ink3),
            ),
          ),
        ),
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? LT.ink : null,
            border: Border.all(color: LT.ink, width: 1.5),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: LT.mono,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: selected ? Colors.white : LT.ink,
            ),
          ),
        ),
      );
}

/// Grey explanatory panel.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.margin = const EdgeInsets.fromLTRB(20, 12, 20, 0)});
  final String text;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        color: LT.band,
        child: Text(text, style: LT.small.copyWith(fontSize: 12.5)),
      );
}

/// Pale caution fill with ink text — "could not check".
class CautionPanel extends StatelessWidget {
  const CautionPanel({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(14),
        color: LT.caution,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: LT.label),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label.toUpperCase(), style: LT.eyebrow),
            const SizedBox(height: 7),
            child,
            if (hint != null) ...[const SizedBox(height: 6), Text(hint!, style: LT.small.copyWith(fontSize: 12, color: LT.ink3))],
          ],
        ),
      );
}

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String shortMonth(DateTime d) => _months[d.month - 1];
String monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String fullDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
String dateTime(DateTime d) =>
    '${fullDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
