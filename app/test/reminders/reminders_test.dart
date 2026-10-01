import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/reminders/reminder_plan.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10, 30); // after the 8:00 slot, before 14:00
  final anjali = Patient(id: 'a', name: 'Anjali Sharma', dateOfBirth: DateTime(1984), sex: Sex.female);
  final aarav = Patient(id: 'b', name: 'Aarav Sharma', dateOfBirth: DateTime(2019), sex: Sex.male);

  HealthRecord rx(String id, String pid, String title, Dose dose, {DateTime? start, DateTime? end}) => HealthRecord(
        id: id, patientId: pid, kind: RecordKind.prescription, title: title, date: start ?? DateTime(2026, 9, 1),
        source: RecordSource.typedByPatient, dose: dose, endDate: end,
      );

  group('the plan', () {
    test('one reminder per slot with a dose, from now on, for two weeks', () {
      final plan = planReminders(
        people: [(anjali, [rx('m', 'a', 'Metformin 500 mg', const Dose(morning: 1, afternoon: 0, night: 1))])],
        settings: const ReminderSettings(on: true),
        now: now,
      );
      expect(plan.first.at, DateTime(2026, 10, 1, 21), reason: 'this morning has passed and there is no afternoon dose');
      expect(plan.where((p) => p.slot == DoseSlot.afternoon), isEmpty);
      expect(plan, hasLength(27), reason: '13 more mornings + 14 nights');
      expect(plan.map((p) => p.id).toSet(), hasLength(27), reason: 'ids are unique');
    });

    test('a course that ends, or starts later, is reminded only while it runs', () {
      final plan = planReminders(
        people: [(anjali, [
          rx('x', 'a', 'Amoxicillin', const Dose(morning: 1, afternoon: 1, night: 1), end: DateTime(2026, 10, 3)),
          rx('y', 'a', 'Vitamin D', const Dose(morning: 1, afternoon: 0, night: 0), start: DateTime(2026, 10, 10)),
        ])],
        settings: const ReminderSettings(on: true),
        now: now,
      );
      final amox = plan.where((p) => p.items.any((i) => i.record.id == 'x'));
      expect(amox.last.at.isBefore(DateTime(2026, 10, 3)), isTrue);
      final vitD = plan.where((p) => p.items.any((i) => i.record.id == 'y'));
      expect(vitD.first.at, DateTime(2026, 10, 10, 8));
    });

    test('family doses share one reminder; names only when chosen', () {
      final plan = planReminders(
        people: [
          (anjali, [rx('m', 'a', 'Metformin 500 mg', const Dose(morning: 0, afternoon: 0, night: 1))]),
          (aarav, [rx('s', 'b', 'Iron syrup', const Dose(morning: 0, afternoon: 0, night: 2))]),
        ],
        settings: const ReminderSettings(on: true),
        now: now,
      );
      final tonight = plan.first;
      expect(tonight.body(showNames: false), 'Time for 2 medicines. Open LifeTrack to see them.');
      expect(tonight.body(showNames: false), isNot(contains('Metformin')));
      expect(tonight.body(showNames: true, selfPatientId: 'a'), 'You: Metformin 500 mg · Aarav: Iron syrup ×2');
    });

    test('settings survive a round trip, with custom times', () {
      const st = ReminderSettings(on: true, showNames: true, times: {DoseSlot.morning: (7, 15), DoseSlot.afternoon: (13, 0), DoseSlot.night: (22, 30)});
      final back = ReminderSettings.fromJson(st.toJson());
      expect((back.on, back.showNames, back.times[DoseSlot.morning], back.times[DoseSlot.night]), (true, true, (7, 15), (22, 30)));
    });
  });

  group('in the app', () {
    late RecordingScheduler sched;
    Future<AppServices> open() async {
      final s = await AppServices.open(
        bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 2)), remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, reminderScheduler: sched,
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      return s;
    }

    setUp(() => sched = RecordingScheduler());

    test('off until turned on; refused permission keeps it off', () async {
      final s = await open();
      await s.addRecord(rx('m', s.selfPatientId!, 'Metformin 500 mg', const Dose(morning: 1, afternoon: 0, night: 1)));
      expect(sched.scheduled, isEmpty);
      sched.permission = false;
      expect(await s.setReminders(const ReminderSettings(on: true)), isFalse);
      expect(s.reminderSettings.on, isFalse);
      sched.permission = true;
      expect(await s.setReminders(const ReminderSettings(on: true)), isTrue);
      expect(sched.scheduled, isNotEmpty);
    });

    test('adding, correcting and deleting a prescription re-plans', () async {
      final s = await open();
      await s.setReminders(const ReminderSettings(on: true));
      final r = rx('m', s.selfPatientId!, 'Metformin 500 mg', const Dose(morning: 1, afternoon: 0, night: 1));
      await s.addRecord(r);
      expect(sched.scheduled.where((p) => p.slot == DoseSlot.afternoon), isEmpty);
      await s.updateRecord(rx('m', s.selfPatientId!, 'Metformin 500 mg', const Dose(morning: 1, afternoon: 1, night: 1)));
      expect(sched.scheduled.where((p) => p.slot == DoseSlot.afternoon), isNotEmpty);
      await s.deleteRecord(s.records().single);
      expect(sched.scheduled, isEmpty);
    });

    test("today's doses can be ticked, and stay ticked after a restart", () async {
      final bytes = InMemoryByteStore();
      Future<AppServices> o() => AppServices.open(
            bytes: bytes, deviceKey: SecretKey(List.filled(32, 2)), remote: InMemoryRemoteVaultStore(),
            kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
          );
      final s = await o();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.addRecord(rx('m', s.selfPatientId!, 'Metformin 500 mg', const Dose(morning: 1, afternoon: 0, night: 1)));
      expect(s.todaysDoses().map((d) => d.$1), [DoseSlot.morning, DoseSlot.night]);
      await s.markTaken(DoseSlot.morning, 'm', true);
      await s.flush();
      final again = await o();
      expect(again.takenToday(DoseSlot.morning, 'm'), isTrue);
      expect(again.takenToday(DoseSlot.night, 'm'), isFalse);
    });
  });
}
