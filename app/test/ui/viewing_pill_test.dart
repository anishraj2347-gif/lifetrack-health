import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// A caregiver who switched to a child on Records must see the child's name
/// on Share and Insights before acting there.
void main() {
  final now = DateTime(2026, 10, 1, 10);

  Future<AppServices> open({bool child = true}) async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 5)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
      demoTools: true,
    );
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    if (child) {
      await s.addChild(name: 'Aarav Sharma', dob: DateTime(2021), sex: Sex.male, relation: 'son');
      await s.switchTo(s.familyOnPhone().last.id);
    }
    return s;
  }

  Future<void> pump(WidgetTester tester, AppServices s) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
  }

  testWidgets('Share and Insights name the person whose records they act on', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open());
    await pump(tester, s);
    for (final tab in ['Share', 'Insights']) {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aarav Sharma', findRichText: true), findsWidgets, reason: tab);
    }
  });

  testWidgets('the pill switches person', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open());
    await pump(tester, s);
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anjali Sharma (you)'));
    await tester.pumpAndSettle();
    expect(s.currentPatientId, s.selfPatientId);
    expect(find.textContaining('your own records', findRichText: true), findsOneWidget);
  });

  testWidgets('with one person on the phone there is no pill', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open(child: false));
    await pump(tester, s);
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Switch'), findsNothing);
  });
}
