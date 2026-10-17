import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifetrack/main.dart' as app;

/// Frame timing on a real phone, on whatever records it holds (run on a demo
/// build with the sample family). Not an invariant test — a measuring tape:
///   flutter drive --profile --driver=test_driver/perf_driver.dart \
///     --target=integration_test/scroll_perf_test.dart (plus the build's --dart-defines)
/// Results: `build/<action>.timeline_summary.json` (frame build and raster times).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling and switching', (tester) async {
    app.main();
    // The app opens behind the phone's lock: unlock it by hand within 90 s.
    for (var i = 0; i < 360 && find.bySemanticsLabel('Records').evaluate().isEmpty; i++) {
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

    await binding.traceAction(() async {
      for (final tab in ['Reminders', 'Records', 'Insights', 'Share', 'Me']) {
        await scrollTab(tab);
      }
    }, reportKey: 'scroll_tabs');

    await binding.traceAction(() async {
      for (var round = 0; round < 2; round++) {
        for (final tab in ['Records', 'Insights', 'Share', 'Me', 'Reminders']) {
          await tester.tap(find.bySemanticsLabel(tab));
          await tester.pumpAndSettle();
        }
      }
    }, reportKey: 'switch_tabs');
  });
}
