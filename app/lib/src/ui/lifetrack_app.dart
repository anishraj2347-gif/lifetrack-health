import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/app_services.dart';
import '../capture/incoming_files.dart';
import '../security/unlocker.dart';
import 'app_lock.dart';
import 'app_scope.dart';
import 'screens/insights_screen.dart';
import 'screens/me_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/records_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/scan_report_screen.dart';
import 'screens/share_screen.dart';
import 'theme.dart';
import 'widgets/family_bar.dart';
import 'widgets/parts.dart';

/// [boot] assembles the services. Widget tests pass one over an in-memory
/// store — without that, boot waits forever on a platform channel that does
/// not exist under test rather than failing.
class LifeTrackApp extends StatefulWidget {
  const LifeTrackApp({super.key, required this.boot, this.unlocker});
  final Future<AppServices> Function() boot;

  /// The phone's own lock. Null (widget tests) means no lock.
  final Unlocker? unlocker;

  @override
  State<LifeTrackApp> createState() => _LifeTrackAppState();
}

class _LifeTrackAppState extends State<LifeTrackApp> with WidgetsBindingObserver {
  late final Future<AppServices> _services = widget.boot().then((s) {
    appearance.value = themeModeOf(s.themeChoice);
    return s;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appearance.addListener(_apply);
    LT.dark = _resolve();
  }

  @override
  void dispose() {
    appearance.removeListener(_apply);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  bool _resolve() => switch (appearance.value) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      };

  /// Screens read [LT] directly, so a change of mode redraws every element —
  /// keeping the open screens and their state, unlike rebuilding the app.
  void _apply() {
    final d = _resolve();
    if (d == LT.dark || !mounted) return;
    setState(() => LT.dark = d);
    void redraw(Element e) {
      e.markNeedsBuild();
      e.visitChildren(redraw);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (context as Element).visitChildren(redraw);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: _services,
    builder: (context, snap) {
      if (snap.hasData) {
        // Above the Navigator, so pushed routes can see it too.
        return AppScope(services: snap.data!, child: _app(_Root(unlocker: widget.unlocker)));
      }
      if (snap.hasError) return _app(_BootError(error: snap.error!));
      return _app(BootSplash());
    },
  );

  Widget _app(Widget home) => MaterialApp(
        title: 'LifeTrack',
        debugShowCheckedModeBanner: false,
        theme: LT.theme(),
        home: home,
        // Captured by crossfadeTheme when light/dark changes.
        builder: (context, child) => RepaintBoundary(key: themeSnapshotKey, child: child),
      );
}

class _Root extends StatelessWidget {
  const _Root({this.unlocker});
  final Unlocker? unlocker;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.currentPatient == null) {
      return OnboardingScreen(onDone: () => AppScope.changed(context));
    }
    final u = unlocker;
    return u == null ? HomeShell() : AppLockGate(unlocker: u, child: HomeShell());
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  // Built only behind the app lock, so a report shared to LifeTrack from
  // another app opens only once the phone's owner has unlocked it.
  @override
  void initState() {
    super.initState();
    IncomingFiles.listen();
    IncomingFiles.arrivals.addListener(_incoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _incoming());
  }

  @override
  void dispose() {
    IncomingFiles.arrivals.removeListener(_incoming);
    super.dispose();
  }

  Future<void> _incoming() async {
    final files = await IncomingFiles.take();
    if (files.isEmpty || !mounted) return;
    setState(() => _tab = 1);
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => ScanReportScreen(incoming: files)));
    if (mounted) AppScope.changed(context);
  }

  static const _tabs = [
    ('Reminders', LucideIcons.bell),
    ('Records', LucideIcons.fileText),
    ('Insights', LucideIcons.activity),
    ('Share', LucideIcons.qrCode),
    ('Me', LucideIcons.userRound),
  ];

  DateTime? _lastBack;

  /// Back works as in other apps: from another tab it returns to the first;
  /// on the first tab it asks for a second press before leaving. Pages
  /// opened on top close first, as usual.
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: _onBack,
    child: _shell(),
  );

  static const _topBarHeight = 52.0;
  static const _topGap = 8.0;

  /// Content runs under both glass bars: the tab sees the bars as extra
  /// padding (lists scroll beneath them), and the bars blur what passes.
  Widget _shell() => Scaffold(
    extendBody: true,
    body: Builder(builder: (context) {
      final mq = MediaQuery.of(context);
      // A floating glass pill like the tab bar, with a little air around it.
      final top = mq.padding.top + _topGap + _topBarHeight + _topGap;
      return Stack(children: [
        MediaQuery(
          data: mq.copyWith(padding: mq.padding.copyWith(top: top)),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: Offset(0, 0.02), end: Offset.zero).animate(a), child: child),
            ),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: switch (_tab) {
                0 => SafeArea(bottom: false, child: RemindersTab()),
                1 => SafeArea(bottom: false, child: RecordsScreen()),
                2 => InsightsScreen(),
                3 => ShareScreen(),
                _ => MeScreen(),
              },
            ),
          ),
        ),
        Positioned(
          top: mq.padding.top + _topGap,
          left: 12,
          right: 12,
          child: DecoratedBox(
            decoration: ShapeDecoration(shape: StadiumBorder(), shadows: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.35 : 0.10), blurRadius: 24, offset: Offset(0, 8))]),
            child: Glass(
              tint: LT.ground,
              opacity: 0.72,
              child: SizedBox(height: _topBarHeight, child: _TopBar()),
            ),
          ),
        ),
      ]);
    }),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: _tabBar(),
      ),
    ),
  );

  /// Every tab shows its icon and its name: icons alone lose people. The
  /// lime pill marks the one you are on ("selected / now").
  Widget _tabBar() => DecoratedBox(
        decoration: ShapeDecoration(shape: StadiumBorder(), shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: Offset(0, 8))]),
        child: Glass(
          tint: LT.primary,
          opacity: 0.80,
          lightText: true,
          padding: EdgeInsets.all(5),
          child: Stack(children: [
            // One lime pill that slides to the tab you pick, with a little
            // overshoot — instead of one blinking out and another in.
            Positioned.fill(
              child: AnimatedAlign(
                alignment: Alignment(-1 + 2 * _tab / (_tabs.length - 1), 0),
                duration: Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                child: FractionallySizedBox(
                  widthFactor: 1 / _tabs.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(),
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.alphaBlend(Colors.white.withValues(alpha: 0.25), LT.accent), LT.accent]),
                      shadows: [BoxShadow(color: LT.accent.withValues(alpha: 0.35), blurRadius: 12)],
                    ),
                  ),
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Semantics(
                    label: _tabs[i].$1,
                    button: true,
                    selected: i == _tab,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: _tabs[i].$1,
                      textStyle: TextStyle(fontFamily: LT.body, fontSize: 18, color: LT.onDark),
                      triggerMode: TooltipTriggerMode.longPress,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != _tab) HapticFeedback.selectionClick();
                          setState(() => _tab = i);
                        },
                        // The selected label sits on the lime pill.
                        child: GlassTone(
                          tone: i == _tab ? LT.accent : Color.alphaBlend(LT.primary.withValues(alpha: 0.80), Colors.white),
                          child: Container(
                            constraints: BoxConstraints(minHeight: 56),
                            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedScale(
                                  scale: i == _tab ? 1.12 : 1,
                                  duration: Duration(milliseconds: 220),
                                  curve: Curves.easeOutBack,
                                  child: Icon(_tabs[i].$2, size: 20, color: i == _tab ? LT.onAccent : LT.onDarkMuted),
                                ),
                                SizedBox(height: 3),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: Duration(milliseconds: 200),
                                    style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w500, color: i == _tab ? LT.onAccent : LT.onDark),
                                    child: Text(_tabs[i].$1, maxLines: 1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      );
}

/// The app's name above every main screen. Light/dark lives in Me → Appearance.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: Row(children: [
          BrandMark(size: 30),
          SizedBox(width: 10),
          Expanded(child: Text('LifeTrack', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.display, fontSize: 17, fontWeight: FontWeight.w600, color: LT.ink, letterSpacing: -0.3))),
          SizedBox(width: 8),
          Flexible(child: Align(alignment: Alignment.centerRight, child: PersonButton())),
        ]),
      );
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LifeTrack could not open your records', style: LT.title),
            SizedBox(height: 16),
            Text(
              'Nothing has been deleted. Do not reinstall the app — that would remove the key your records need.\n\n$error',
              style: LT.lede,
            ),
          ],
        ),
      ),
    ),
  );
}
