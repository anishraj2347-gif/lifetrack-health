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
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
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

/// Swipe a row sideways to tick it done (or undo it); the row springs back
/// and the tick changes. The checkbox inside still works for anyone who
/// does not swipe.
class SwipeToggle extends StatelessWidget {
  const SwipeToggle({required super.key, required this.done, required this.onToggle, required this.child, this.doneLabel = 'Taken'});
  final bool done;
  final Future<void> Function(bool) onToggle;
  final Widget child;
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    Widget side(Alignment a) => Container(
          alignment: a,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: done ? LT.raised : LT.primary, borderRadius: BorderRadius.circular(LT.radius)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(done ? LucideIcons.undo2 : LucideIcons.check, size: 18, color: done ? LT.ink : LT.onDark),
            SizedBox(width: 8),
            Text(done ? 'Not yet' : doneLabel, style: TextStyle(fontFamily: LT.body, fontSize: 14, fontWeight: FontWeight.w600, color: done ? LT.ink : LT.onDark)),
          ]),
        );
    return Dismissible(
      key: key!,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      background: side(Alignment.centerLeft),
      secondaryBackground: side(Alignment.centerRight),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        await onToggle(!done);
        return false;
      },
      child: child,
    );
  }
}

/// The photos bundled with the app (assets/photos). Shipped inside the APK,
/// never fetched: the release build has no INTERNET permission.
abstract final class Photos {
  static const family = 'assets/photos/family.jpg';
  static const report = 'assets/photos/report.jpg';
  static const doctor = 'assets/photos/doctor.jpg';
  static const pills = 'assets/photos/pills.jpg';
  static const reading = 'assets/photos/reading.jpg';
  static const parent = 'assets/photos/parent.jpg';
}

/// A rounded photo that drifts in slowly as it appears. Decorative: screen
/// readers skip it, and no text is ever laid over it (contrast_test reads
/// text against solid colour only). A little dimmer in dark mode.
class PhotoBanner extends StatelessWidget {
  const PhotoBanner(this.asset, {super.key, this.height = 180, this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4)});
  final String asset;
  final double height;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final width = MediaQuery.sizeOf(context).width;
    final image = Image.asset(
      asset,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      cacheWidth: (width * dpr).round().clamp(320, 1080),
      color: LT.dark ? Colors.black.withValues(alpha: 0.18) : null,
      colorBlendMode: LT.dark ? BlendMode.darken : null,
    );
    return Padding(
      padding: margin,
      child: Appear(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LT.radiusLg),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: still
                ? image
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.08, end: 1),
                    duration: Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    builder: (context, s, child) => Transform.scale(scale: s, child: child),
                    child: image,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The "done" picture: a black disc that pops in, a ring that ripples out,
/// and a tick that draws itself. Black and white, never lime — "done" is not
/// a selection, and never a health status.
class DoneMark extends StatelessWidget {
  const DoneMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: 'Done',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: Duration(milliseconds: 900),
        builder: (context, t, _) => CustomPaint(size: Size.square(size * 1.5), painter: _DonePainter(t, LT.button, LT.onButton, LT.ink3)),
      ),
    );
  }
}

class _DonePainter extends CustomPainter {
  _DonePainter(this.t, this.fill, this.ink, this.ring);
  final double t;
  final Color fill, ink, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 3;
    // 0–0.4: disc pops (with a little overshoot); 0.2–1: ring ripples out
    // and fades; 0.4–0.85: the tick draws.
    final pop = Curves.easeOutBack.transform((t / 0.4).clamp(0, 1));
    final rip = Curves.easeOut.transform(((t - 0.2) / 0.8).clamp(0, 1));
    final draw = Curves.easeInOut.transform(((t - 0.4) / 0.45).clamp(0, 1));
    if (rip > 0 && rip < 1) {
      canvas.drawCircle(c, r * (1 + 0.5 * rip), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ring.withValues(alpha: 0.5 * (1 - rip)));
    }
    canvas.drawCircle(c, r * pop, Paint()..color = fill);
    if (draw > 0) {
      final path = Path()
        ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.12, c.dy + r * 0.32)
        ..lineTo(c.dx + r * 0.45, c.dy - r * 0.30);
      final m = path.computeMetrics().first;
      canvas.drawPath(m.extractPath(0, m.length * draw), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ink);
    }
  }

  @override
  bool shouldRepaint(_DonePainter old) => old.t != t || old.fill != fill;
}

/// A short "done" moment over everything: the tick and a word, then it
/// fades by itself. Safe to call just before closing a screen — it is
/// placed on the app's root overlay.
void celebrate(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  HapticFeedback.mediumImpact();
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Celebration(message: message, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;
  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  // One controller for the whole moment (no timers): in 0–15%, hold to
  // 80%, out by 100%.
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: 1500))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final v = _c.value;
            final o = v < 0.15 ? v / 0.15 : v > 0.8 ? (1 - v) / 0.2 : 1.0;
            return Opacity(opacity: o.clamp(0, 1), child: child);
          },
          child: Center(
            child: Material(
              color: LT.surface,
              elevation: 8,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(LT.radiusLg),
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, 18, 28, 22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DoneMark(size: 72),
                  Text(widget.message, textAlign: TextAlign.center, style: LT.label.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
}
