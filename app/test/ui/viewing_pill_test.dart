import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/widgets/family_bar.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// A caregiver who switched to a child must see the child's name on every
/// tab (the top bar's person button) before acting there.
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

  testWidgets('every tab names the person whose records it acts on', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open());
    await pump(tester, s);
    for (final tab in ['Reminders', 'Records', 'Insights', 'Share', 'Me']) {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(PersonButton), matching: find.text('Aarav')), findsOneWidget, reason: tab);
    }
  });

  testWidgets('the person button switches person', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open());
    await pump(tester, s);
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PersonButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anjali Sharma (you)'));
    await tester.pumpAndSettle();
    expect(s.currentPatientId, s.selfPatientId);
    expect(find.descendant(of: find.byType(PersonButton), matching: find.text('You')), findsOneWidget);
  });

  testWidgets('with one person on the phone the button is just the avatar', (tester) async {
    late AppServices s;
    await tester.runAsync(() async => s = await open(child: false));
    await pump(tester, s);
    expect(find.byType(PersonButton), findsOneWidget);
    expect(find.descendant(of: find.byType(PersonButton), matching: find.text('You')), findsNothing);
  });
}
