import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/reminders/reminder_plan.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vaccines/uip_schedule.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final birth = DateTime(2026, 8, 20);
  final now = DateTime(2026, 10, 1, 10, 30);

  test('due dates follow the schedule from the date of birth', () {
    DateTime due(String code) => uipSchedule.firstWhere((d) => d.code == code).dueDate(birth);
    expect(due('bcg'), birth);
    expect(due('penta-1'), DateTime(2026, 10, 1), reason: '6 weeks');
    expect(due('penta-2'), DateTime(2026, 10, 29), reason: '10 weeks');
    expect(due('mr-1'), DateTime(2027, 5, 20), reason: '9 months');
    expect(due('dpt-b2'), DateTime(2031, 8, 20), reason: '5 years');
  });

  test('status: given, due (age reached, not marked), upcoming', () {
    final rows = vaccineStatus(birth, {'bcg': VaccineGiven(on: birth, place: 'District hospital')}, now);
    final st = {for (final (d, s, _) in rows) d.code: s};
    expect(st['bcg'], VaccineStatus.given);
    expect(st['opv-0'], VaccineStatus.due);
    expect(st['penta-1'], VaccineStatus.due);
    expect(st['penta-2'], VaccineStatus.upcoming);
  });

  group('in the app', () {
    late InMemoryByteStore bytes;
    late InMemoryRemoteVaultStore vault;
    late RecordingScheduler sched;
    Future<AppServices> open([InMemoryByteStore? b]) => AppServices.open(
          bytes: b ?? bytes, deviceKey: SecretKey(List.filled(32, 4)), remote: vault,
          kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, reminderScheduler: sched,
        );
    setUp(() {
      bytes = InMemoryByteStore();
      vault = InMemoryRemoteVaultStore();
      sched = RecordingScheduler();
    });

    test('marking a dose given is kept, logged, and survives backup and restore', () async {
      final s = await open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final baby = await s.addChild(name: 'Aarav Sharma', dob: birth, sex: Sex.male, relation: 'son');
      await s.markVaccine(baby.id, 'bcg', VaccineGiven(on: birth, place: 'District hospital'));
      expect(s.vaccinesOf(baby.id)['bcg']!.place, 'District hospital');
      expect(s.audit.entriesFor(baby.id).first.detail, 'BCG given on 2026-08-20 at District hospital');
      final kit = await s.setUpBackup();

      final fresh = await open(InMemoryByteStore());
      await fresh.restoreFromBackup(account: kit.account, password: kit.password);
      expect(fresh.vaccinesOf(baby.id)['bcg']!.on, birth);
    });

    test('a dose due in the next two weeks gets a reminder on its day, names hidden by default', () async {
      final s = await open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.addChild(name: 'Aarav Sharma', dob: DateTime(2026, 8, 25), sex: Sex.male, relation: 'son'); // 6 weeks = 6 Oct
      await s.setReminders(const ReminderSettings(on: true));
      final shots = sched.scheduled.where((r) => r.vaccine != null).toList();
      expect(shots.map((r) => r.at).toSet(), {DateTime(2026, 10, 6, 8)});
      expect(shots.map((r) => r.vaccine!.$2), containsAll(['OPV 1', 'Pentavalent 1']));
      expect(shots.first.body(showNames: false), 'A vaccination is due today. Open LifeTrack to see it.');
      expect(shots.first.body(showNames: true), startsWith('Aarav: '));
    });

    test('erasing the child removes their vaccination record', () async {
      final s = await open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final baby = await s.addChild(name: 'Aarav Sharma', dob: birth, sex: Sex.male, relation: 'son');
      await s.markVaccine(baby.id, 'bcg', VaccineGiven(on: birth));
      await s.switchTo(baby.id);
      await s.eraseProfile();
      final again = await open();
      expect(again.vaccinesOf(baby.id), isEmpty);
    });
  });
}
