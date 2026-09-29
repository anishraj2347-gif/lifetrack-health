import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    ('Records', LucideIcons.fileText),
    ('Insights', LucideIcons.activity),
    ('Share', LucideIcons.qrCode),
    ('Me', LucideIcons.userRound),
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
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: LT.rule)), color: LT.ground),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(LT.radius),
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        height: 58,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: i == _tab ? LT.band : Colors.transparent,
                          borderRadius: BorderRadius.circular(LT.radius),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(_tabs[i].$2, size: 20, color: i == _tab ? LT.ink : LT.inactive),
                          const SizedBox(height: 4),
                          Text(
                            _tabs[i].$1,
                            style: TextStyle(fontFamily: LT.body, fontSize: 11.5, fontWeight: FontWeight.w500, color: i == _tab ? LT.ink : LT.inactive),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
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
