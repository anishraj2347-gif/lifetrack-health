import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/model/vital_reading.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
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
}
