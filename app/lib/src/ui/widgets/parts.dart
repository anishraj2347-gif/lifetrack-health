import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// Page header: muted label, title, optional trailing, bottom border.
class Masthead extends StatelessWidget {
  const Masthead({super.key, required this.eyebrow, required this.title, this.trailing, this.description});
  final String eyebrow;
  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: LT.eyebrow),
                  const SizedBox(height: 4),
                  Text(title, style: LT.title),
                  if (description != null) ...[const SizedBox(height: 6), Text(description!, style: LT.small)],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

/// Section label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 10)});
  final String text;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text, style: LT.eyebrow.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: LT.ink2)),
      );
}

enum ButtonVariant { primary, outline, destructive, ghost }

/// shadcn Button. `outline: true` and `color` are kept for call sites that
/// predate [variant].
class SlabButton extends StatelessWidget {
  const SlabButton(this.label, {super.key, required this.onPressed, this.outline = false, this.color, this.icon, this.variant});
  final String label;
  final VoidCallback? onPressed;
  final bool outline;
  final Color? color;
  final IconData? icon;
  final ButtonVariant? variant;

  @override
  Widget build(BuildContext context) {
    final v = variant ?? (outline ? ButtonVariant.outline : (color == LT.signal ? ButtonVariant.destructive : ButtonVariant.primary));
    final enabled = onPressed != null;
    final (bg, fg, border) = switch (v) {
      ButtonVariant.primary => (LT.primary, const Color(0xFFFAFAFA), null),
      ButtonVariant.destructive => (LT.signal, Colors.white, null),
      ButtonVariant.outline => (LT.ground, LT.ink, LT.rule),
      ButtonVariant.ghost => (Colors.transparent, LT.ink, null),
    };
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LT.radius),
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(LT.radius),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 14.5, fontWeight: FontWeight.w500, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Toggle pill (shadcn ToggleGroup item).
class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
    return Material(
      color: selected ? LT.primary : LT.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? LT.primary : LT.rule),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(text, style: TextStyle(fontFamily: LT.body, fontSize: 13.5, fontWeight: FontWeight.w500, color: selected ? Colors.white : LT.ink)),
        ),
      ),
    );
  }
}

enum BadgeTone { neutral, outline, signal, trace, caution }

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.tone = BadgeTone.neutral});
  final String text;
  final BadgeTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      BadgeTone.neutral => (LT.band, LT.ink, LT.band),
      BadgeTone.outline => (LT.ground, LT.ink2, LT.rule),
      BadgeTone.signal => (const Color(0xFFFFF7ED), LT.signal, const Color(0xFFFED7AA)),
      BadgeTone.trace => (const Color(0xFFECFDF5), LT.trace, const Color(0xFFA7F3D0)),
      BadgeTone.caution => (LT.caution, LT.cautionInk, LT.cautionBorder),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// shadcn Card.
class ShadCard extends StatelessWidget {
  const ShadCard({super.key, required this.child, this.onTap, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10), this.padding = const EdgeInsets.all(16), this.color = LT.ground, this.borderColor = LT.rule});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radiusLg), side: BorderSide(color: borderColor)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// shadcn Alert, neutral.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0), this.icon = LucideIcons.info});
  final String text;
  final EdgeInsets margin;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: LT.band, borderRadius: BorderRadius.circular(LT.radiusLg)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: LT.ink2),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: LT.small.copyWith(color: LT.ink2))),
        ]),
      );
}

/// shadcn Alert, warning tone — "could not check".
class CautionPanel extends StatelessWidget {
  const CautionPanel({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LT.caution,
          borderRadius: BorderRadius.circular(LT.radiusLg),
          border: Border.all(color: LT.cautionBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Icon(LucideIcons.triangleAlert, size: 16, color: LT.cautionInk)),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: LT.cautionInk),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LT.label.copyWith(color: LT.cautionInk, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                child,
              ]),
            ),
          ),
        ]),
      );
}

/// Label + control + optional description (shadcn form field).
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: LT.label.copyWith(fontSize: 14)),
            const SizedBox(height: 8),
            child,
            if (hint != null) ...[const SizedBox(height: 6), Text(hint!, style: LT.small.copyWith(fontSize: 12.5))],
          ],
        ),
      );
}

/// A select-like button (date pickers etc.).
class FieldButton extends StatelessWidget {
  const FieldButton({super.key, required this.text, required this.onTap, this.icon = LucideIcons.calendar, this.placeholder = false});
  final String text;
  final VoidCallback onTap;
  final IconData icon;
  final bool placeholder;
  @override
  Widget build(BuildContext context) => Material(
        color: LT.ground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radius), side: const BorderSide(color: LT.rule)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LT.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 16, color: LT.ink3),
              const SizedBox(width: 10),
              Text(text, style: LT.label.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: placeholder ? LT.inactive : LT.ink)),
            ]),
          ),
        ),
      );
}

/// Rounded square icon tile.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color = LT.ink, this.background = LT.band});
  final IconData icon;
  final Color color;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(LT.radius)),
        child: Icon(icon, size: 19, color: color),
      );
}

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String shortMonth(DateTime d) => _monthNames[d.month - 1].substring(0, 3);
String monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String fullDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
String dateTime(DateTime d) =>
    '${fullDate(d)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
