import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/clinical_profile.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/clinical_profile_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/ui/widgets/summary_view.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 11, 6, 9);
  Future<AppServices> open([InMemoryByteStore? b]) async {
    final s = await AppServices.open(
      bytes: b ?? InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 7)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
    );
    if (s.currentPatientId == null) await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    return s;
  }

  group('one allergy list', () {
    const penicillin = Allergy(substance: 'Penicillin', reaction: 'rash');

    test('saving the list fills the Emergency ID, keeps its other fields, and is logged', () async {
      final s = await open();
      final me = s.selfPatientId!;
      await s.saveEmergencyCard(me, const EmergencyCard(bloodType: 'B+', contactName: 'Vikram'));
      await s.saveClinicalProfile(const ClinicalProfile(allergies: [penicillin, Allergy(substance: 'Peanuts')], conditions: [Condition(name: 'Asthma', sinceYear: 2019)]));
      final card = await s.emergency.load(me);
      expect(card.allergies, 'Penicillin, Peanuts');
      expect((card.bloodType, card.contactName), ('B+', 'Vikram'));
      expect(s.clinicalProfile().updatedAt, now);
      final logged = s.auditEntries().singleWhere((e) => e.dataClass == DataClass.allergies);
      expect(logged.action, AuditAction.edit);
      expect(logged.detail, contains('allergies, conditions and family illnesses'));
    });

    test('the same list goes to the doctor', () async {
      final s = await open();
      await s.saveClinicalProfile(const ClinicalProfile(allergies: [penicillin]));
      expect(s.ownSummary()['allergies'], [
        {'substance': 'Penicillin', 'reaction': 'rash'},
      ]);
    });

    test('editing the card changes the list and keeps a named reaction', () async {
      final s = await open();
      final me = s.selfPatientId!;
      await s.saveClinicalProfile(const ClinicalProfile(allergies: [penicillin]));
      await s.saveEmergencyCard(me, const EmergencyCard(allergies: 'Penicillin, Sulfa drugs'));
      final list = s.clinicalProfile().allergies;
      expect(list.map((a) => a.substance), ['Penicillin', 'Sulfa drugs']);
      expect(list.first.reaction, 'rash');
      expect(s.ownSummary()['allergies'], hasLength(2));
    });

    test('every change to the card or the list is in the log (#13)', () async {
      final s = await open();
      final me = s.selfPatientId!;
      await s.saveEmergencyCard(me, const EmergencyCard(allergies: 'Latex'));
      expect(s.auditEntries().map((e) => e.detail), containsAll(['Emergency ID edited', 'allergy list changed from the Emergency ID']));
      final n = s.auditEntries().length;
      await s.saveEmergencyCard(me, const EmergencyCard(allergies: 'Latex'));
      expect(s.auditEntries(), hasLength(n), reason: 'nothing changed');
    });

    test('a long list is cut on the card, never in the record, and survives a card edit', () async {
      final s = await open();
      final me = s.selfPatientId!;
      final many = [for (var i = 0; i < 20; i++) Allergy(substance: 'Substance number $i')];
      await s.saveClinicalProfile(ClinicalProfile(allergies: many));
      final card = await s.emergency.load(me);
      expect(card.allergies.length, lessThanOrEqualTo(EmergencyCard.maxFieldLength));
      expect(card.allergies, endsWith('more'));
      expect(card.validate(), isEmpty);
      await s.saveEmergencyCard(me, card);
      expect(s.clinicalProfile().allergies, hasLength(20), reason: 'an unchanged line changes nothing');
      await s.saveEmergencyCard(me, card.withAllergies(card.allergies.replaceFirst('Substance number 0, ', ''), now));
      expect(s.clinicalProfile().allergies, hasLength(19));
      expect(s.clinicalProfile().allergies.last.substance, 'Substance number 19');
    });

    test('"no known allergies" is a statement, and reaches the card and the doctor', () async {
      final s = await open();
      final me = s.selfPatientId!;
      expect(s.ownSummary().containsKey('noKnownAllergies'), isFalse, reason: 'empty is not "none"');
      await s.saveClinicalProfile(const ClinicalProfile(noneKnown: true));
      expect((await s.emergency.load(me)).allergies, noKnownAllergies);
      expect(s.ownSummary()['noKnownAllergies'], isTrue);
      await s.saveEmergencyCard(me, const EmergencyCard(allergies: 'Latex'));
      expect(s.clinicalProfile().noneKnown, isFalse);
      expect(s.ownSummary().containsKey('noKnownAllergies'), isFalse);
    });

    test('a card filled in before the list existed becomes the list on next open', () async {
      final bytes = InMemoryByteStore();
      final s = await open(bytes);
      await s.emergency.save(s.selfPatientId!, const EmergencyCard(allergies: 'Penicillin; Latex'));
      final again = await open(bytes);
      expect(again.clinicalProfile().allergies.map((a) => a.substance), ['Penicillin', 'Latex']);
      expect(again.auditEntries().where((e) => (e.detail ?? '').contains('copied from the Emergency ID')), hasLength(1));
    });

    test('stored and read back', () {
      final p = ClinicalProfile.fromJson(const ClinicalProfile(noneKnown: true).toJson());
      expect(p.noneKnown, isTrue);
      expect(ClinicalProfile.fromJson(const {}).noneKnown, isFalse);
    });
  });

  group('the editor', () {
    Future<AppServices> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.reset);
      final s = (await t.runAsync(open))!;
      await t.pumpWidget(AppScope(
        services: s,
        child: MaterialApp(
          theme: LT.theme(),
          home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const ClinicalProfileScreen())), child: const Text('open')))),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return s;
    }

    Finder hint(String h) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == h);

    testWidgets('allergy, condition and family illness are all entered and saved', (t) async {
      final s = await pump(t);
      await t.tap(find.text('Add an allergy'));
      await t.pumpAndSettle();
      await t.enterText(hint('Allergic to, e.g. Penicillin'), 'Penicillin');
      await t.enterText(hint('What happens, e.g. rash (optional)'), 'rash');
      await t.tap(find.text('Add a condition'));
      await t.pumpAndSettle();
      await t.enterText(hint('Condition, e.g. Asthma'), 'Asthma');
      await t.enterText(hint('Since which year (optional)'), '2019');
      await t.tap(find.text('Add a family illness'));
      await t.pumpAndSettle();
      await t.enterText(hint('Illness, e.g. Heart attack'), 'Heart attack');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.textContaining('Say who in the family'), findsOneWidget);
      await t.tap(find.text('Who'), warnIfMissed: false);
      await t.pumpAndSettle();
      await t.tap(find.text('Father').last);
      await t.pumpAndSettle();
      await t.enterText(hint('Their age when it began (optional)'), '58');
      await t.tap(find.text('Save'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();

      final p = s.clinicalProfile();
      expect((p.allergies.single.substance, p.allergies.single.reaction), ('Penicillin', 'rash'));
      expect((p.conditions.single.name, p.conditions.single.sinceYear), ('Asthma', 2019));
      expect((p.familyIllnesses.single.relation, p.familyIllnesses.single.ageAtOnset), (Relation.father, 58));
      expect(find.text('Allergies and conditions'), findsNothing, reason: 'back on the screen before');
    });

    testWidgets('an empty list says what it means', (t) async {
      await pump(t);
      expect(find.textContaining('It does not mean there are none'), findsOneWidget);
      await t.tap(find.text(noKnownAllergies));
      await t.pumpAndSettle();
      expect(find.textContaining('It does not mean there are none'), findsNothing);
    });

    testWidgets('a bad year is refused', (t) async {
      final s = await pump(t);
      await t.tap(find.text('Add a condition'));
      await t.pumpAndSettle();
      await t.enterText(hint('Condition, e.g. Asthma'), 'Asthma');
      await t.enterText(hint('Since which year (optional)'), '3000');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.textContaining('between 1900 and 2026'), findsOneWidget);
      expect(s.clinicalProfile().conditions, isEmpty);
    });
  });

  testWidgets('the patient\'s own summary says when allergies are not recorded', (t) async {
    final s = (await t.runAsync(open))!;
    await t.pumpWidget(MaterialApp(theme: LT.theme(), home: Scaffold(body: SingleChildScrollView(child: SummaryView(bundle: s.ownSummary())))));
    await t.pump();
    expect(find.text('Allergies: not recorded'), findsOneWidget);
  });
}
