import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
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
    expect(find.text('Who are these\nrecords for?'), findsOneWidget);
    await tester.ensureVisible(find.text('EXPLORE WITH SAMPLE RECORDS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXPLORE WITH SAMPLE RECORDS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('FINISH SETUP'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('FINISH SETUP'));
    await tester.pumpAndSettle();
  }

  testWidgets('sample onboarding lands on the timeline', (tester) async {
    await onboardWithSamples(tester);
    expect(find.text('Anjali Sharma'), findsOneWidget);
    expect(find.text('Lipid panel'), findsOneWidget);
  });

  testWidgets('a record shows values without judging them until Insights is on', (tester) async {
    await onboardWithSamples(tester);
    await tester.tap(find.text('Lipid panel'));
    await tester.pumpAndSettle();
    expect(find.text('132 mg/dL'), findsOneWidget);
    expect(find.textContaining('Turn on Insights'), findsOneWidget);
    expect(find.textContaining('above the reference range'), findsNothing);
  });

  testWidgets('Insights asks first, then shows findings and what was not checked', (tester) async {
    await onboardWithSamples(tester);
    await tester.tap(find.text('INSIGHTS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN ON FOR 24 HOURS'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('LDL cholesterol was 132 mg/dL'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('LDL cholesterol was 132 mg/dL'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('could not be compared'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('could not be compared'), findsOneWidget);
    expect(find.textContaining('Nothing in your records stands out'), findsNothing);
  });

  testWidgets('the access log records the Insights grant and its reads', (tester) async {
    await onboardWithSamples(tester);
    await tester.tap(find.text('INSIGHTS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN ON FOR 24 HOURS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ME'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Access log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('On-device insights read'), findsWidgets);
    expect(find.textContaining('You gave access'), findsOneWidget);
  });
}
