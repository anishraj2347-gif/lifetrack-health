import 'package:flutter/material.dart';

import '../app/app_services.dart';
import 'app_scope.dart';
import 'screens/insights_screen.dart';
import 'screens/me_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/records_screen.dart';
import 'screens/share_screen.dart';
import 'theme.dart';

/// [boot] assembles the services. Widget tests pass one over an in-memory
/// store — without that, boot waits forever on a platform channel that does
/// not exist under test rather than failing.
class LifeTrackApp extends StatefulWidget {
  const LifeTrackApp({super.key, required this.boot});
  final Future<AppServices> Function() boot;

  @override
  State<LifeTrackApp> createState() => _LifeTrackAppState();
}

class _LifeTrackAppState extends State<LifeTrackApp> {
  late final Future<AppServices> _services = widget.boot();

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
        future: _services,
        builder: (context, snap) {
          if (snap.hasData) {
            // Above the Navigator, so pushed routes can see it too.
            return AppScope(services: snap.data!, child: _app(const _Root()));
          }
          if (snap.hasError) return _app(_BootError(error: snap.error!));
          return _app(const Scaffold(body: Center(child: CircularProgressIndicator())));
        },
      );

  Widget _app(Widget home) => MaterialApp(
        title: 'LifeTrack',
        debugShowCheckedModeBanner: false,
        theme: LT.theme(),
        home: home,
      );
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.currentPatient == null) {
      return OnboardingScreen(onDone: () => AppScope.changed(context));
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _tabs = [
    ('Records', Icons.article_outlined),
    ('Insights', Icons.bar_chart),
    ('Share', Icons.qr_code_2),
    ('Me', Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: switch (_tab) {
            0 => const RecordsScreen(),
            1 => const InsightsScreen(),
            2 => const ShareScreen(),
            _ => const MeScreen(),
          },
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: LT.ink, width: 2)), color: LT.ground),
          child: SafeArea(
            top: false,
            child: Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: i == _tab ? LT.ink : Colors.transparent, width: 3))),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_tabs[i].$2, size: 20, color: i == _tab ? LT.ink : LT.inactive),
                        const SizedBox(height: 5),
                        Text(
                          _tabs[i].$1.toUpperCase(),
                          style: TextStyle(fontFamily: LT.mono, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: i == _tab ? LT.ink : LT.inactive),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LifeTrack could not open your records', style: LT.title),
              const SizedBox(height: 16),
              Text(
                'Nothing has been deleted. Do not reinstall the app — that would remove the key your records need.\n\n$error',
                style: LT.lede,
              ),
            ]),
          ),
        ),
      );
}
