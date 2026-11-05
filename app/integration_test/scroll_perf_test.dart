import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifetrack/main.dart' as app;

/// Frame timing on a real phone, on whatever records it holds (run on a demo
/// build; a fresh install is given the sample family). Not an invariant test
/// — a measuring tape:
///   flutter drive --profile --driver=test_driver/perf_driver.dart \
///     --target=integration_test/scroll_perf_test.dart (plus the build's --dart-defines)
/// Results: `build/<action>.frame_summary.json` (frame build and raster times
/// from the phone's own frame timings; no VM service connection needed).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling and switching', (tester) async {
    app.main();
    // The app opens behind the phone's lock: unlock it by hand within 90 s.
    // A fresh install opens on the welcome screen; real taps do not reach the
    // app during a test, so the test walks the sample-family setup itself,
    // tapping each step once (scrolled into view first: on a phone the
    // buttons sit below the fold).
    final setup = [
      'Look around with sample records',
      'I understand my records are only on this phone until I turn on backup.',
      'Continue',
      'Finish setup',
    ];
    final done = <String>{};
    // LifeTrack's own lock screen: the test taps Unlock (again every 10 s while
    // it stays up), and the phone's fingerprint/PIN prompt — a system screen,
    // which real touches do reach — is answered by hand.
    final unlock = find.text('Unlock');
    for (var i = 0; i < 360 && find.bySemanticsLabel('Records').evaluate().isEmpty; i++) {
      if (i % 40 == 0 && unlock.evaluate().isNotEmpty) {
        debugPrint('perf: tapping Unlock — answer the fingerprint/PIN prompt');
        await tester.tap(unlock.first);
      }
      for (final label in setup) {
        final f = find.text(label);
        if (done.contains(label) || f.evaluate().isEmpty) continue;
        debugPrint('perf: setup — $label');
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        done.add(label);
        break;
      }
      if (i % 40 == 0) debugPrint('perf: waiting for the home screen; on screen: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(4).join(' | ')}');
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();

    Future<void> scrollTab(String tab) async {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, -900), 2500);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, 900), 2500);
        await tester.pumpAndSettle();
      }
    }

    await binding.watchPerformance(() async {
      for (final tab in ['Reminders', 'Records', 'Insights', 'Share', 'Me']) {
        await scrollTab(tab);
      }
    }, reportKey: 'scroll_tabs');

    await binding.watchPerformance(() async {
      for (var round = 0; round < 2; round++) {
        for (final tab in ['Records', 'Insights', 'Share', 'Me', 'Reminders']) {
          await tester.tap(find.bySemanticsLabel(tab));
          await tester.pumpAndSettle();
        }
      }
    }, reportKey: 'switch_tabs');
  });
}
