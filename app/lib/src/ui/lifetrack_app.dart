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
      return _app(Scaffold(body: Center(child: CircularProgressIndicator())));
    },
  );

  Widget _app(Widget home) => MaterialApp(title: 'LifeTrack', debugShowCheckedModeBanner: false, theme: LT.theme(), home: home);
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

  Widget _shell() => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(children: [
        _TopBar(),
        Expanded(
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
                0 => RemindersTab(),
                1 => RecordsScreen(),
                2 => InsightsScreen(),
                3 => ShareScreen(),
                _ => MeScreen(),
              },
            ),
          ),
        ),
      ]),
    ),
    extendBody: true,
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
  Widget _tabBar() => Container(
        padding: EdgeInsets.all(5),
        decoration: ShapeDecoration(color: LT.primary, shape: StadiumBorder()),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: Semantics(
                  label: _tabs[i].$1,
                  button: true,
                  selected: i == _tab,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i != _tab) HapticFeedback.selectionClick();
                      setState(() => _tab = i);
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      constraints: BoxConstraints(minHeight: 56),
                      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      decoration: ShapeDecoration(color: i == _tab ? LT.accent : Colors.transparent, shape: StadiumBorder()),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: i == _tab ? 1.12 : 1,
                            duration: Duration(milliseconds: 200),
                            child: Icon(_tabs[i].$2, size: 20, color: i == _tab ? LT.onAccent : LT.onDarkMuted),
                          ),
                          SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _tabs[i].$1,
                              maxLines: 1,
                              style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w500, color: i == _tab ? LT.onAccent : LT.onDarkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// The app's name above every main screen. Light/dark lives in Me → Appearance.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: LT.primary, borderRadius: BorderRadius.circular(8)),
            child: Icon(LucideIcons.heartPulse, size: 15, color: LT.onDark),
          ),
          SizedBox(width: 8),
          Text('LifeTrack', style: TextStyle(fontFamily: LT.display, fontSize: 16, fontWeight: FontWeight.w600, color: LT.ink, letterSpacing: -0.2)),
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
