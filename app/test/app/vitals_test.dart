import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lifetrack/src/ai/insight.dart';
import 'package:lifetrack/src/ai/plane_a/banned_phrases.dart';
import 'package:lifetrack/src/ai/plane_a/critical_check.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/model/vital_reading.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/vitals_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 9);
  late InMemoryRemoteVaultStore vault;
  Future<AppServices> open([InMemoryByteStore? b]) => AppServices.open(
        bytes: b ?? InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 7)), remote: vault,
        kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
      );
  VitalReading reading(String pid) => VitalReading(id: 'v1', patientId: pid, at: now, kind: VitalKind.bloodPressure, systolic: 128, diastolic: 82, pulse: 72);

  setUp(() => vault = InMemoryRemoteVaultStore());

  test('readings are checked for slips, shown plainly, and survive a restart', () async {
    expect(VitalReading.check(systolic: 128, diastolic: 182), isNotNull);
    expect(VitalReading.check(systolic: 1280, diastolic: 82), isNotNull);
    expect(VitalReading.check(glucose: 5), isNotNull);
    expect(VitalReading.check(systolic: 128, diastolic: 82, pulse: 72), isNull);
    expect(reading('p').display, '128/82 mmHg · pulse 72');
    expect(VitalReading(id: 'g', patientId: 'p', at: now, kind: VitalKind.glucose, glucose: 112, context: GlucoseContext.afterMeal).display, '112 mg/dL · after a meal');

    final bytes = InMemoryByteStore();
    final s = await open(bytes);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.addVital(reading(s.selfPatientId!));
    final again = await open(bytes);
    expect(again.vitalsOf(again.selfPatientId!).single.systolic, 128);
  });

  test('backed up only when personal data is included', () async {
    final s = await open();
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.addVital(reading(s.selfPatientId!));
    final kit = await s.setUpBackup();
    final a = await open();
    await a.restoreFromBackup(account: kit.account, password: kit.password);
    expect(a.vitalsOf(a.selfPatientId!), isEmpty, reason: 'local-only by default');

    await s.setBackupIncludesNotes(true);
    await s.settle();
    final b = await open();
    await b.restoreFromBackup(account: kit.account, password: kit.password);
    expect(b.vitalsOf(b.selfPatientId!), hasLength(1));
  });

  test('erasing the profile erases its readings', () async {
    final bytes = InMemoryByteStore();
    final s = await open(bytes);
    final p = await s.createProfile(name: 'Solo', dob: DateTime(1990), sex: Sex.male);
    await s.addVital(reading(p.id));
    await s.eraseProfile();
    final again = await open(bytes);
    expect(again.vitalsOf(p.id), isEmpty);
  });

  group('a dangerous reading gets a person, not a celebration', () {
    final adult = Patient(id: 'p', name: 'A', dateOfBirth: DateTime(1984), sex: Sex.female);
    final child = Patient(id: 'c', name: 'C', dateOfBirth: DateTime(2020), sex: Sex.male);
    VitalReading bp(int top, int bottom, {int? pulse, DateTime? on}) => VitalReading(id: 'v', patientId: 'p', at: on ?? now, kind: VitalKind.bloodPressure, systolic: top, diastolic: bottom, pulse: pulse);
    VitalReading sugar(double g) => VitalReading(id: 'g', patientId: 'p', at: now, kind: VitalKind.glucose, glucose: g, context: GlucoseContext.random);
    InsightRun check(VitalReading v, [Patient? who]) => CriticalCheck.vital(patient: who ?? adult, reading: v, at: now);

    test('sugar 40 and BP 220/130 are urgent and name 108', () {
      for (final v in [sugar(40), bp(220, 130)]) {
        final i = check(v).insights.single;
        expect(i.severity, Severity.urgentCare);
        expect(i.action, contains('call 108'));
        expect(firstBannedPhrase('${i.finding} ${i.action}'), isNull);
      }
      expect(check(sugar(40)).insights.single.finding, contains('below 54 mg/dL'));
      expect(check(bp(220, 130)).insights.single.finding, contains('220/130 mmHg'));
    });

    test('where the limits sit', () {
      expect(check(bp(180, 100)).insights.single.severity, Severity.urgentCare);
      expect(check(bp(150, 120)).insights.single.severity, Severity.urgentCare);
      expect(check(bp(179, 119)).needsPrompt, isFalse);
      expect(check(sugar(53)).insights.single.severity, Severity.urgentCare);
      expect(check(sugar(60)).insights.single.severity, Severity.contactDoctorToday);
      expect(check(sugar(70)).needsPrompt, isFalse);
      expect(check(sugar(320)).insights.single.severity, Severity.contactDoctorToday);
      expect(check(sugar(500)).insights.single.severity, Severity.urgentCare);
      expect(check(bp(85, 55)).insights.single.severity, Severity.contactDoctorToday);
      expect(check(bp(65, 40)).insights.single.severity, Severity.urgentCare);
      expect(check(bp(120, 80, pulse: 150)).insights.single.severity, Severity.contactDoctorToday);
    });

    test('an adult low limit is never applied to a child; a crisis high one still is (#10)', () {
      expect(check(bp(85, 55, pulse: 140), child).needsPrompt, isFalse);
      expect(check(bp(190, 125), child).insights.single.severity, Severity.urgentCare);
      expect(check(sugar(40), child).insights.single.severity, Severity.urgentCare);
    });

    test('a reading typed in days later reaches a person today', () {
      final old = check(bp(220, 130, on: now.subtract(const Duration(days: 30)))).insights.single;
      expect(old.severity, Severity.contactDoctorToday);
      expect(old.finding, contains('more than a week old'));
    });

    test('saving one is logged as raising a prompt, without Insights on', () async {
      final s = await open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final v = VitalReading(id: 'v9', patientId: s.selfPatientId!, at: now, kind: VitalKind.glucose, glucose: 40);
      await s.addVital(v);
      expect(s.insightsEnabled(), isFalse);
      expect(s.criticalCheckVital(v).insights.single.severity, Severity.urgentCare);
      expect(s.auditEntries().last.detail, contains('danger-level prompt'));
    });
  });

  testWidgets('the screen shows the prompt instead of "Reading saved"', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = (await t.runAsync(() async {
      final x = await open();
      await x.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      return x;
    }))!;
    await t.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: const VitalsScreen())));
    await t.pumpAndSettle();
    await t.tap(find.text('Sugar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add a reading'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Sugar (mg/dL)'), '40');
    await t.tap(find.text('Save reading'));
    await t.pumpAndSettle();
    expect(find.text('Reading saved'), findsNothing);
    expect(find.text('Saved. Please read this now'), findsOneWidget);
    expect(find.text('Call 108'), findsOneWidget);
    await t.tap(find.text('I have read this'));
    await t.pumpAndSettle();
    expect(find.text('Saved. Please read this now'), findsNothing);
    expect(find.text('Save reading'), findsNothing);
    expect(find.textContaining('40 mg/dL'), findsWidgets);
  });
}
