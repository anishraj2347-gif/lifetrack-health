import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
/// Dark mode (1 Oct 2026): every surface and ink has a dark value; [dark]
/// says which is in force and the app root rebuilds everything when it
/// changes. Lime and the fill-only colours are the same in both modes.
/// Dark text variants of the semantic colours, measured the same way:
///
///   trace  #10B981 emerald-500 · signal #F97316 orange-500 (text on dark)
///   worst pair 38.9 under protanopia (deutan 55.6); vs lime ≥ 26.7;
///   ≥ 5.3:1 on every dark surface. Fills stay #C2410C (white 5.2:1).
/// Follow phone, light or dark — the patient's choice (Me → Appearance).
/// The app root listens and redraws everything when it changes.
final appearance = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode themeModeOf(String choice) => switch (choice) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

abstract final class LT {
  /// Set by the app root from the patient's choice and the phone's setting.
  static bool dark = false;

  static Color _p(int light, int darkValue) => Color(dark ? darkValue : light);

  static Color get ground => _p(0xFFE3E3DC, 0xFF121210); // page
  static Color get surface => _p(0xFFF4F4EF, 0xFF1D1D1A); // card
  static Color get raised => _p(0xFFFBFBF8, 0xFF272724); // pills, inputs, icon circles
  static Color get band => surface; // muted panels
  static Color get rule => _p(0xFFD4D3CC, 0xFF3A3935);
  static Color get ink => _p(0xFF0E0E0E, 0xFFF2F2EC);
  static Color get ink2 => _p(0xFF45443F, 0xFFD0CFC8);
  static Color get ink3 => _p(0xFF64635D, 0xFFA6A59E); // ≥ 4.5:1 on ground and cards (contrast_test)
  static Color get inactive => _p(0xFFA9A8A1, 0xFF6E6D67);

  /// Hero cards and the bottom bar: black in light mode, lifted in dark.
  static Color get primary => _p(0xFF0E0E0E, 0xFF0B0B0A); // dark: below the glass, so heroes still stand out
  static Color get onDark => _p(0xFFF4F4EF, 0xFFF2F2EC);
  static Color get onDarkMuted => _p(0xFF9A9A94, 0xFFA6A59E);

  /// A chip or empty dot sitting on a hero card.
  static Color get onDarkChip => _p(0xFF2A2A28, 0xFF45453F);

  /// Primary buttons: black on the light page, cream on the dark one.
  static Color get button => _p(0xFF0E0E0E, 0xFFF2F2EC);
  static Color get onButton => _p(0xFFF4F4EF, 0xFF121210);

  /// Selection / "now" only.
  static const accent = Color(0xFFEEF36A);

  /// Anything drawn on lime.
  static const onAccent = Color(0xFF0E0E0E);

  /// Text and icons on the page.
  static Color get trace => _p(0xFF065F46, 0xFF10B981);
  static Color get signal => _p(0xFFC2410C, 0xFFF97316);

  /// On their own pale fills (badges, tiles) — the same in both modes.
  static const traceInk = Color(0xFF065F46);
  static const signalFill = Color(0xFFC2410C); // also the fill behind white text
  static const caution = Color(0xFFFEF3C7);
  static const cautionBorder = Color(0xFFE3C878);
  static const cautionInk = Color(0xFF78350F);

  static const radius = 16.0;
  static const radiusLg = 22.0;

  static const display = 'Poppins';
  static const body = 'Poppins';
  static const mono = 'Poppins';

  static TextStyle get eyebrow => TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w500, color: ink2);
  static TextStyle get title => TextStyle(fontFamily: display, fontSize: 26, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.6, color: ink);
  static TextStyle get hero => TextStyle(fontFamily: display, fontSize: 30, fontWeight: FontWeight.w600, height: 1.12, letterSpacing: -0.8, color: ink);
  static TextStyle get lede => TextStyle(fontFamily: body, fontSize: 15, height: 1.55, color: ink2);
  static TextStyle get label => TextStyle(fontFamily: body, fontSize: 15, fontWeight: FontWeight.w500, color: ink, letterSpacing: -0.1);
  /// Secondary text. 14 sp in ink2: much of the consent wording is set in
  /// this style, and it has to be readable by older eyes (design review,
  /// 10 Oct 2026). ink3 is kept for timestamps and hints only.
  static TextStyle get small => TextStyle(fontFamily: body, fontSize: 14, height: 1.5, color: ink2);
  static TextStyle get meta => TextStyle(fontFamily: body, fontSize: 12.5, height: 1.4, color: ink3);
  static TextStyle get data => TextStyle(fontFamily: mono, fontSize: 14.5, fontWeight: FontWeight.w600, color: ink, fontFeatures: [FontFeature.tabularFigures()]);

  /// The colour wash behind every page: soft, warm blobs that are never a
  /// health colour (no red, no green) and never lime.
  static List<(Alignment, double, Color)> get washes => dark
      ? [(Alignment(-1.1, -0.9), 1.1, Color(0xFF27445E)), (Alignment(1.2, -0.2), 1.0, Color(0xFF463257)), (Alignment(-0.4, 1.1), 1.2, Color(0xFF553D22))]
      : [(Alignment(-1.1, -0.9), 1.1, Color(0xFFBFD4EC)), (Alignment(1.2, -0.2), 1.0, Color(0xFFDCCBEE)), (Alignment(-0.4, 1.1), 1.2, Color(0xFFF4D2B8))];

  /// What a glass card can have behind it at worst, for contrast: the
  /// darkest wash in light mode (dark text), the lightest in dark mode.
  static Color get washExtreme => _p(0xFFC8D7E8, 0xFF324458);

  static ThemeData theme() {
    final none = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(radius)), borderSide: BorderSide(color: raised));
    final scheme = (dark ? ColorScheme.dark() : ColorScheme.light()).copyWith(
      primary: button,
      onPrimary: onButton,
      secondary: accent,
      onSecondary: onAccent,
      // Tonal buttons and the like must not turn lime ("selected" only).
      secondaryContainer: raised,
      onSecondaryContainer: ink,
      error: signal,
      surface: surface,
      onSurface: ink,
      outline: rule,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      // Pages paint their own colour wash (see Backdrop), so scaffolds are clear.
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: body,
      // A soft material ripple under the finger.
      splashFactory: InkRipple.splashFactory,
      splashColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final p in TargetPlatform.values) p: const BackdropTransitions(),
      }),
      colorScheme: scheme,
      dividerColor: rule,
      // Lucide everywhere: the back arrow too.
      actionIconTheme: ActionIconThemeData(backButtonIconBuilder: (_) => Icon(LucideIcons.arrowLeft, size: 22)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface.withValues(alpha: 0.96),
        showDragHandle: true,
        dragHandleColor: rule,
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg))),
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: TextStyle(fontFamily: body, fontSize: 15, color: ink),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: TextStyle(fontFamily: display, fontSize: 20, fontWeight: FontWeight.w600, color: ink),
        contentTextStyle: TextStyle(fontFamily: body, fontSize: 14.5, height: 1.5, color: ink2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      // Glass fields: see-through fill with a bright rim, ink when focused.
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: raised.withValues(alpha: 0.78),
        hintStyle: TextStyle(color: ink3),
        border: none,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.85)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: ink, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // One tick style everywhere: round.
      checkboxTheme: CheckboxThemeData(
        shape: CircleBorder(),
        side: BorderSide(color: ink, width: 1.3),
        checkColor: WidgetStatePropertyAll(dark ? onAccent : accent),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? accent : primary) : Colors.transparent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? onAccent : onDark) : ink3),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? accent : primary) : raised),
        trackOutlineColor: WidgetStatePropertyAll(rule),
      ),
      textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light).textTheme.apply(fontFamily: body, bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: ink),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        headerHeadlineStyle: TextStyle(fontFamily: display, fontSize: 26, fontWeight: FontWeight.w600, color: ink),
        todayBorder: BorderSide(color: ink),
        dayShape: WidgetStatePropertyAll(CircleBorder()),
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: surface),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ink),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ink)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: button,
        contentTextStyle: TextStyle(fontFamily: body, color: onButton),
        shape: StadiumBorder(),
      ),
    );
  }
}

/// The page background: the ground colour with the soft colour wash.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: LT.ground,
        child: Stack(fit: StackFit.passthrough, children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _WashPainter(LT.washes)))),
          child,
        ]),
      );
}

class _WashPainter extends CustomPainter {
  _WashPainter(this.washes);
  final List<(Alignment, double, Color)> washes;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide;
    for (final (at, scale, c) in washes) {
      final centre = at.alongSize(size);
      canvas.drawCircle(
        centre,
        r * scale,
        Paint()..shader = RadialGradient(colors: [c.withValues(alpha: 0.85), c.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centre, radius: r * scale)),
      );
    }
  }

  @override
  bool shouldRepaint(_WashPainter old) => old.washes.first.$3 != washes.first.$3;
}

/// The usual page transition, with every page painted on the [Backdrop].
class BackdropTransitions extends PageTransitionsBuilder {
  const BackdropTransitions();
  static const _inner = ZoomPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      _inner.buildTransitions(route, context, animation, secondaryAnimation, Backdrop(child: child));
}
