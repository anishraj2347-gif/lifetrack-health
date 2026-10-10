import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: LT.eyebrow),
                  SizedBox(height: 4),
                  Text(title, style: LT.title),
                  if (description != null) ...[SizedBox(height: 6), Text(description!, style: LT.small)],
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
    final v = variant ?? (outline ? ButtonVariant.outline : (color == LT.signal || color == LT.signalFill ? ButtonVariant.destructive : ButtonVariant.primary));
    final enabled = onPressed != null;
    final (bg, fg, border) = switch (v) {
      ButtonVariant.primary => (LT.button, LT.onButton, null),
      ButtonVariant.destructive => (LT.signalFill, Colors.white, null),
      ButtonVariant.outline => (LT.raised, LT.ink, null),
      ButtonVariant.ghost => (Colors.transparent, LT.ink, null),
    };
    return Opacity(
      opacity: enabled ? 1 : 0.65, // disabled stays readable (contrast_test)
      child: Pressable(
        enabled: enabled,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    v == ButtonVariant.primary || v == ButtonVariant.destructive ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
                    onPressed!();
                  },
            customBorder: StadiumBorder(),
            // Grows for large system text instead of cutting the label off.
            child: Container(
              constraints: BoxConstraints(minHeight: 52),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), SizedBox(width: 8)],
                Flexible(
                  child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.body, fontSize: 14.5, fontWeight: FontWeight.w600, color: fg)),
                ),
              ]),
            ),
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
      color: selected ? LT.button : LT.raised,
      shape: StadiumBorder(),
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        customBorder: StadiumBorder(),
        child: Container(
          constraints: BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(text, style: TextStyle(fontFamily: LT.body, fontSize: 13.5, fontWeight: FontWeight.w500, color: selected ? LT.onButton : LT.ink)),
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
    final dark = OnDark.of(context);
    final (bg, fg, border) = switch (tone) {
      BadgeTone.neutral when dark => (LT.onDarkChip, LT.onDark, LT.onDarkChip),
      BadgeTone.outline when dark => (Colors.transparent, LT.onDark, LT.onDarkMuted),
      BadgeTone.neutral => (LT.raised, LT.ink, LT.raised),
      BadgeTone.outline => (Colors.transparent, LT.ink2, LT.rule),
      BadgeTone.signal => (Color(0xFFFFF7ED), LT.signalFill, Color(0xFFFED7AA)),
      BadgeTone.trace => (Color(0xFFECFDF5), LT.traceInk, Color(0xFFA7F3D0)),
      BadgeTone.caution => (LT.caution, LT.cautionInk, LT.cautionBorder),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 11.5, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

/// shadcn Card.
class ShadCard extends StatelessWidget {
  const ShadCard({super.key, required this.child, this.onTap, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12), this.padding = const EdgeInsets.all(16), this._color, this.borderColor});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final Color? _color;
  Color get color => _color ?? LT.surface;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Appear(
          child: Pressable(
            enabled: onTap != null,
            child: _card(),
          ),
        ),
      );

  Widget _card() => Material(
          color: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radiusLg), side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: padding,
              // On a black card, anything that does not set its own colour is
              // light, and badges switch to their light form.
              child: color.computeLuminance() < 0.2
                  ? OnDark(child: DefaultTextStyle.merge(style: TextStyle(color: LT.onDark), child: IconTheme.merge(data: IconThemeData(color: LT.onDarkMuted), child: child)))
                  : child,
            ),
          ),
        );
}

/// Sinks a little under the finger, so a tap is felt before anything opens.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (widget.enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: Duration(milliseconds: _down ? 90 : 160),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Fades and rises into place the first time it is built. Off when the
/// phone asks for less motion.
class Appear extends StatelessWidget {
  const Appear({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final total = delay + Duration(milliseconds: 280);
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
    );
  }
}

/// Marks a dark surface, so parts placed on it (badges) use light colours.
class OnDark extends InheritedWidget {
  const OnDark({super.key, required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<OnDark>() != null;
  @override
  bool updateShouldNotify(OnDark oldWidget) => false;
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
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(color: LT.raised, borderRadius: BorderRadius.circular(LT.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: LT.ink2),
          SizedBox(width: 10),
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
        margin: EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LT.caution,
          borderRadius: BorderRadius.circular(LT.radiusLg),
          border: Border.all(color: LT.cautionBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(top: 1), child: Icon(LucideIcons.triangleAlert, size: 16, color: LT.cautionInk)),
          SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: LT.cautionInk),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LT.label.copyWith(color: LT.cautionInk, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: LT.label.copyWith(fontSize: 13.5, color: LT.ink2)),
            SizedBox(height: 8),
            child,
            if (hint != null) ...[SizedBox(height: 6), Text(hint!, style: LT.small.copyWith(fontSize: 12.5))],
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
        color: LT.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radius)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LT.radius),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 16, color: LT.ink3),
              SizedBox(width: 10),
              Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: LT.label.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: placeholder ? LT.ink3 : LT.ink))),
            ]),
          ),
        ),
      );
}

/// Rounded square icon tile.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color, this.background});
  final IconData icon;
  final Color? color;
  final Color? background;
  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: background ?? LT.raised, shape: BoxShape.circle),
        child: Icon(icon, size: 19, color: color ?? (background == LT.accent ? LT.onAccent : LT.ink)),
      );
}

/// Black circular icon button.
class RoundButton extends StatelessWidget {
  const RoundButton(this.icon, {super.key, required this.onTap, this.dark = true, this.size = 48});
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;
  final double size;
  @override
  Widget build(BuildContext context) => Material(
        color: dark ? LT.button : LT.raised,
        shape: CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: CircleBorder(),
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 19, color: dark ? LT.onButton : LT.ink)),
        ),
      );
}

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String shortMonth(DateTime d) => _monthNames[d.month - 1].substring(0, 3);
String monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String fullDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
String dateTime(DateTime d) => '${fullDate(d)}, ${time(d)}';

String time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// An error in words a patient can act on — never a stack of exception names.
String plainError(Object e) {
  final t = '$e';
  if (RegExp(r'SocketException|ClientException|Connection (refused|reset|closed)|Failed host lookup|TimeoutException|HandshakeException').hasMatch(t)) {
    return 'LifeTrack\'s server could not be reached. Check the internet connection and try again.';
  }
  if (e is FormatException) return e.message;
  if (e is ArgumentError && e.message != null) return '${e.message}';
  if (e is StateError) return e.message;
  return 'Something went wrong. Please try again.';
}
