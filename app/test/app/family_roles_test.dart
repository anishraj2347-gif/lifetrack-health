import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/family/family_role.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/widgets/family_bar.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';
import 'package:lifetrack/src/ui/screens/family_overview_screen.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10);

  Future<AppServices> open() async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 3)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
    );
    await s.createProfile(name: 'Rahul Verma', dob: DateTime(1990, 5, 1), sex: Sex.male);
    return s;
  }

  Future<Patient> adult(AppServices s, String name, int year, Sex sex, FamilyRole role) =>
      s.addDelegatingAdult(name: name, dob: DateTime(year), sex: sex, relation: role.name, typedName: name);

  test('adults take any role to the head; a child under 18 only son or daughter', () async {
    final s = await open();
    for (final (n, y, sex, r) in [
      ('Suresh Verma', 1960, Sex.male, FamilyRole.father),
      ('Meena Verma', 1963, Sex.female, FamilyRole.mother),
      ('Priya Verma', 1992, Sex.female, FamilyRole.wife),
      ('Neha Verma', 1995, Sex.female, FamilyRole.sister),
      ('Kamla Devi', 1958, Sex.female, FamilyRole.motherInLaw),
    ]) {
      await adult(s, n, y, sex, r);
    }
    await s.addChild(name: 'Aarav Verma', dob: DateTime(2020), sex: Sex.male, relation: FamilyRole.son.name);
    expect(s.familyOnPhone(), hasLength(7));

    await expectLater(s.addChild(name: 'Riya Verma', dob: DateTime(2012), sex: Sex.female, relation: FamilyRole.sister.name), throwsA(isA<CustodyRefused>()),
        reason: 'the head is not a minor sister\'s parent');
    await expectLater(adult(s, 'Pal', 1990, Sex.male, FamilyRole.son).then((_) => null), completes, reason: 'an adult son is fine');
    await expectLater(s.addDelegatingAdult(name: 'X Y', dob: DateTime(1990), sex: Sex.male, relation: 'friend', typedName: 'X Y'), throwsA(isA<CustodyRefused>()));
  });

  test('the role can be corrected, logged; a child stays son or daughter', () async {
    final s = await open();
    final dad = await adult(s, 'Suresh Verma', 1960, Sex.male, FamilyRole.uncle);
    await s.setRole(dad.id, FamilyRole.father);
    expect(s.custodyOf(dad.id)!.relation, 'father');
    expect(s.audit.entriesFor(dad.id).map((e) => e.detail), contains('Role changed: uncle → father'));
    expect(s.custodyOf(dad.id)!.kind, CustodyKind.delegatedByAdult, reason: 'a label, not authority');

    final kid = await s.addChild(name: 'Aarav Verma', dob: DateTime(2020), sex: Sex.male, relation: 'son');
    await expectLater(s.setRole(kid.id, FamilyRole.nephew), throwsA(isA<CustodyRefused>()));
    await s.setRole(kid.id, FamilyRole.daughter);
    await expectLater(s.setRole(s.selfPatientId!, FamilyRole.father), throwsA(isA<CustodyRefused>()));
  });

  test('older relations still read: spouse, mother, son', () {
    expect(FamilyRole.describe('spouse'), 'spouse');
    expect(FamilyRole.describe('fatherInLaw'), 'father-in-law');
    expect(FamilyRole.describe('someone typed'), 'someone typed');
    expect(FamilyRole.parse('mother')!.generation, -1);
    expect(FamilyRole.parse('grandson')!.generation, 2);
  });

  testWidgets('the overview groups the family around the head; tapping a person opens their records', (tester) async {
    late AppServices s;
    late Patient dad;
    await tester.runAsync(() async {
      s = await open();
      dad = await adult(s, 'Suresh Verma', 1960, Sex.male, FamilyRole.father);
      await adult(s, 'Neha Verma', 1995, Sex.female, FamilyRole.sister);
      await s.addChild(name: 'Aarav Verma', dob: DateTime(2020), sex: Sex.male, relation: 'son');
      await s.switchTo(s.selfPatientId!);
    });
    // Tall enough for the family tree and the list below it at once.
    tester.view.physicalSize = const Size(1080, 5600);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PersonButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SlabButton, 'Family'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyOverviewScreen), findsOneWidget);
    expect(find.text("Rahul's family"), findsOneWidget);
    for (final t in ['Parents and elders', 'Head of family', 'Spouse, brothers and sisters', 'Children']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('Head of family · you'), findsOneWidget);
    expect(find.textContaining('Father · M'), findsOneWidget);
    expect(find.textContaining('Sister · F'), findsOneWidget);
    expect(find.textContaining('Son · M'), findsOneWidget);
    expect(find.text('Grandparents'), findsNothing);

    // Order on screen: elders, head, own generation, children.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Parents and elders') < y('Head of family'), isTrue);
    expect(y('Head of family') < y('Spouse, brothers and sisters'), isTrue);
    expect(y('Spouse, brothers and sisters') < y('Children'), isTrue);

    // The tree shows him too (first name); open him from the list.
    expect(find.text('Suresh'), findsOneWidget);
    await tester.tap(find.text('Suresh Verma'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyOverviewScreen), findsNothing);
    expect(s.currentPatientId, dad.id);
  });
}
