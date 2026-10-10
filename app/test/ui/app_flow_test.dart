import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  Future<AppServices> boot() => AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 9)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => DateTime(2026, 4, 1, 9),
      );

  Future<void> onboardWithSamples(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: boot));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget, reason: 'a welcome before any form');
    await tester.scrollUntilVisible(find.text('Look around with sample records'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look around with sample records'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Checkbox), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Continue'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Finish setup'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Finish setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish setup'));
    await tester.pumpAndSettle();
    // The app opens on Reminders; the timeline is the next tab.
    expect(find.text('Reminders'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Records'));
    await tester.pumpAndSettle();
  }

  testWidgets('light and dark are chosen in Me → Appearance; no switch on the main screens', (tester) async {
    await onboardWithSamples(tester);
    expect(find.bySemanticsLabel('Switch to dark mode'), findsNothing);
    expect(find.bySemanticsLabel('Switch to light mode'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dark'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(LT.dark, isTrue);
    final s = AppScope.of(tester.element(find.byType(HomeShell)));
    expect(s.themeChoice, 'dark');
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(LT.dark, isFalse);
    appearance.value = ThemeMode.system;
    LT.dark = false;
  });

  testWidgets('sample onboarding lands on the timeline', (tester) async {
    await onboardWithSamples(tester);
    expect(find.text('Anjali Sharma'), findsOneWidget);
    expect(find.text('HbA1c'), findsWidgets);
  });

  testWidgets('a record shows values without judging them until Insights is on', (tester) async {
    await onboardWithSamples(tester);
    await tester.scrollUntilVisible(find.text('Lipid panel'), 200, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
    await tester.pumpAndSettle();
    // Two lipid panels in the samples (March and September); the newer is first.
    await tester.tap(find.text('Lipid panel').first);
    await tester.pumpAndSettle();
    expect(find.text('118 mg/dL'), findsOneWidget);
    expect(find.textContaining('Turn on Insights'), findsOneWidget);
    expect(find.textContaining('above the reference range'), findsNothing);
  });

  testWidgets('Insights asks first, then shows findings and what was not checked', (tester) async {
    await onboardWithSamples(tester);
    await tester.tap(find.bySemanticsLabel('Insights'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Turn on for 24 hours'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 24 hours'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('LDL cholesterol was 118 mg/dL'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('LDL cholesterol was 118 mg/dL'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('could not be compared'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('could not be compared'), findsOneWidget);
    expect(find.textContaining('Nothing in your records stands out'), findsNothing);
  });

  testWidgets('the access log records the Insights grant and its reads', (tester) async {
    await onboardWithSamples(tester);
    await tester.tap(find.bySemanticsLabel('Insights'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Turn on for 24 hours'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 24 hours'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Access log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('On-device insights read'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('You gave access'), 300,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
    expect(find.textContaining('You gave access'), findsOneWidget);
    // The Insights view holds the grant and its reads, and nothing else.
    await tester.scrollUntilVisible(find.textContaining('Insights ·'), -300,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
    await tester.ensureVisible(find.textContaining('Insights ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Insights ·'), warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Reads by on-device insights'), findsOneWidget);
    expect(find.textContaining('added'), findsNothing);
  });
}
