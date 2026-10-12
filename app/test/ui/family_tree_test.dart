import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/family_overview_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/ui/widgets/family_tree.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// The tree is drawn from each person's role every time: whoever is added
/// takes their place in it with no further step.
void main() {
  Future<AppServices> phone({bool demo = false}) => AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 4)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => DateTime(2026, 10, 12, 10),
        demoTools: demo,
      );

  Future<void> show(WidgetTester tester, AppServices s) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: FamilyOverviewScreen())));
    await tester.pumpAndSettle();
  }

  Finder inTree(String text) => find.descendant(of: find.byType(FamilyTree), matching: find.text(text));

  testWidgets('a person added later appears in the tree under their role', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await phone();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984, 6, 14), sex: Sex.female);
      await s.addChild(name: 'Aarav Sharma', dob: DateTime(2014, 4, 11), sex: Sex.male, relation: 'son');
    });
    await show(tester, s);
    expect(inTree('Aarav'), findsOneWidget);
    expect(inTree('Son'), findsOneWidget);
    final aaravY = tester.getTopLeft(inTree('Aarav')).dy;
    final headY = tester.getTopLeft(inTree('Anjali')).dy;
    expect(aaravY, greaterThan(headY), reason: 'a child sits a row below the head');

    await tester.runAsync(() => s.addDelegatingAdult(name: 'Kamla Gupta', dob: DateTime(1956, 7, 8), sex: Sex.female, relation: 'mother', typedName: 'Kamla Gupta'));
    await show(tester, s);
    expect(inTree('Kamla'), findsOneWidget);
    expect(tester.getTopLeft(inTree('Kamla')).dy, lessThan(tester.getTopLeft(inTree('Anjali')).dy), reason: 'a parent sits a row above');
  });

  testWidgets('the sample family makes a ten-person tree over four generations', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await phone(demo: true);
      await s.createProfile(name: '', dob: DateTime(1990), sex: Sex.unspecified, demo: true);
      expect(await s.addDemoFamily(), 9);
      expect(await s.addDemoFamily(), 0, reason: 'running it again adds nobody twice');
    });
    expect(s.familyOnPhone(), hasLength(10));
    await show(tester, s);
    for (final name in ['Savitri', 'Prakash', 'Kamla', 'Ramesh', 'Sunita', 'Anjali', 'Vikram', 'Rohit', 'Aarav', 'Myra']) {
      expect(inTree(name), findsOneWidget, reason: name);
    }
    final rows = {for (final n in ['Savitri', 'Kamla', 'Anjali', 'Myra']) tester.getTopLeft(inTree(n)).dy};
    expect(rows, hasLength(4), reason: 'four generations, four rows');
    expect(s.vaccinesOf(s.familyOnPhone().firstWhere((p) => p.name == 'Myra Sharma').id), isNotEmpty);
  });

  test('outside a demonstration build there is no sample family', () async {
    final s = await phone();
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    expect(() => s.addDemoFamily(), throwsA(anything));
  });
}
