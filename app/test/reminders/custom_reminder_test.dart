import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/reminders/custom_reminder.dart';
import 'package:lifetrack/src/reminders/reminder_plan.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10, 30); // a Thursday
  final anjali = Patient(id: 'a', name: 'Anjali Sharma', dateOfBirth: DateTime(1984), sex: Sex.female);
  final ramesh = Patient(id: 'b', name: 'Ramesh Sharma', dateOfBirth: DateTime(1955), sex: Sex.male);

  CustomReminder bp({String id = 'r1', String pid = 'a', List<(int, int)> times = const [(9, 0), (19, 0)], Repeat repeat = Repeat.daily, Set<int> days = const {}, DateTime? start, DateTime? end, bool paused = false}) =>
      CustomReminder(id: id, patientId: pid, title: 'Check BP', note: 'sitting, after 5 min rest', times: times, repeat: repeat, days: days, start: start ?? DateTime(2026, 10, 1), end: end, paused: paused);

  group('when it happens', () {
    test('every day, some days, once, until an end date, never while paused', () {
      expect(bp().occursOn(DateTime(2026, 10, 9)), isTrue);
      expect(bp(start: DateTime(2026, 10, 5)).occursOn(DateTime(2026, 10, 4)), isFalse);
      expect(bp(end: DateTime(2026, 10, 3)).occursOn(DateTime(2026, 10, 3, 23)), isTrue);
      expect(bp(end: DateTime(2026, 10, 3)).occursOn(DateTime(2026, 10, 4)), isFalse);
      final mwf = bp(repeat: Repeat.weekdays, days: {DateTime.monday, DateTime.wednesday, DateTime.friday});
      expect([for (var d = 1; d <= 7; d++) mwf.occursOn(DateTime(2026, 10, d))], [false, true, false, false, true, false, true]); // 1 Oct is a Thursday
      final once = bp(repeat: Repeat.once, start: DateTime(2026, 10, 2));
      expect([once.occursOn(DateTime(2026, 10, 1)), once.occursOn(DateTime(2026, 10, 2)), once.occursOn(DateTime(2026, 10, 3))], [false, true, false]);
      expect(bp(paused: true).occursOn(now), isFalse);
      expect(mwf.scheduleLabel((d) => '${d.day}'), 'Mon, Wed, Fri');
    });

    test('refuses what cannot be reminded', () {
      expect(bp().problem(), isNull);
      expect(CustomReminder(id: 'x', patientId: 'a', title: '  ', times: const [(9, 0)], start: now).problem(), isNotNull);
      expect(bp(times: const []).problem(), isNotNull);
      expect(bp(repeat: Repeat.weekdays).problem(), isNotNull, reason: 'no day picked');
      expect(bp(end: DateTime(2026, 9, 1)).problem(), isNotNull);
    });

    test('round-trips through JSON', () {
      final r = bp(repeat: Repeat.weekdays, days: {1, 3}, end: DateTime(2026, 12, 1), paused: true);
      expect(CustomReminder.fromJson(r.toJson()).toJson(), r.toJson());
    });
  });

  test('the plan: each time on each day from now, own ids, names off the lock screen by default', () {
    final plan = planCustomReminders(people: [(anjali, [bp()]), (ramesh, [bp(id: 'r2', pid: 'b', times: const [(20, 0)], repeat: Repeat.once)])], now: now);
    expect(plan.first.at, DateTime(2026, 10, 1, 19), reason: '9:00 has passed today');
    expect(plan.where((p) => p.customFor == anjali), hasLength(27));
    expect(plan.where((p) => p.customFor == ramesh), hasLength(1));
    expect(plan.every((p) => p.id >= 2000), isTrue);
    expect(plan.map((p) => p.id).toSet(), hasLength(plan.length));
    final r = plan.firstWhere((p) => p.customFor == ramesh);
    expect(r.title, 'Reminder');
    expect(r.body(showNames: false, selfPatientId: 'a'), 'You have a reminder. Open LifeTrack to see it.');
    expect(r.body(showNames: true, selfPatientId: 'a'), 'Ramesh: Check BP — sitting, after 5 min rest');
    expect(plan.first.body(showNames: true, selfPatientId: 'a'), startsWith('Check BP'));
  });

  group('on the phone', () {
    late RecordingScheduler sched;
    late InMemoryRemoteVaultStore server;
    Future<AppServices> phone(int key) async => AppServices.open(
          bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, key)), remote: server,
          kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, reminderScheduler: sched,
        );
    setUp(() {
      sched = RecordingScheduler();
      server = InMemoryRemoteVaultStore();
    });

    test('making one turns reminders on and schedules it; edit, pause and delete re-plan; all logged', () async {
      final s = await phone(1);
      final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      expect(s.reminderSettings.on, isFalse);
      expect(await s.saveCustomReminder(bp(pid: me.id)), isTrue);
      expect(s.reminderSettings.on, isTrue);
      expect(sched.scheduled.where((p) => p.custom != null), hasLength(27));
      expect(s.todaysCustom().map((t) => (t.$1, t.$2)), [(9, 0), (19, 0)]);

      await s.saveCustomReminder(bp(pid: me.id, times: const [(7, 30)]));
      expect(s.customRemindersOf(me.id), hasLength(1), reason: 'same id replaces');
      expect(sched.scheduled.where((p) => p.custom != null), hasLength(13));

      await s.saveCustomReminder(s.customRemindersOf(me.id).single.copyWith(paused: true));
      expect(sched.scheduled.where((p) => p.custom != null), isEmpty);

      await s.markCustomDone(s.customRemindersOf(me.id).single, 7, 30, true);
      expect(s.customDoneToday(s.customRemindersOf(me.id).single, 7, 30), isTrue);

      await s.deleteCustomReminder(s.customRemindersOf(me.id).single);
      expect(s.customRemindersOf(me.id), isEmpty);
      final log = s.audit.entriesFor(me.id).where((e) => e.action == AuditAction.edit).map((e) => e.detail).toList();
      expect(log, containsAll(['reminder added: Check BP', 'reminder changed: Check BP', 'reminder deleted: Check BP']));
      expect(() => s.saveCustomReminder(bp(pid: me.id, times: const [])), throwsArgumentError);
    });

    test('kept across a restart; backed up only with personal notes; erased with the profile', () async {
      final bytes = InMemoryByteStore();
      Future<AppServices> o() => AppServices.open(
            bytes: bytes, deviceKey: SecretKey(List.filled(32, 3)), remote: server,
            kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, reminderScheduler: sched,
          );
      final s = await o();
      final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.saveCustomReminder(bp(pid: me.id));
      expect((await o()).customRemindersOf(me.id), hasLength(1));

      final plain = await s.setUpBackup(includeNotes: false);
      final p2 = await phone(4);
      await p2.restoreFromBackup(account: plain.account, password: plain.password);
      expect(p2.customRemindersOf(me.id), isEmpty, reason: 'personal, like notes (#6)');

      await s.setBackupIncludesNotes(true);
      await s.backUpNow();
      final p3 = await phone(5);
      await p3.restoreFromBackup(account: plain.account, password: plain.password);
      expect(p3.customRemindersOf(me.id).single.title, 'Check BP');
    });
  });

  testWidgets('create from the Reminders tab, then edit and delete it', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 6)), remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, reminderScheduler: RecordingScheduler(),
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create a reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Drink water');
    await tester.tap(find.text('Some days'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Mon'));
    await tester.tap(find.bySemanticsLabel('Thu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save reminder'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();

    expect(find.text('Drink water'), findsWidgets);
    expect(find.textContaining('11:00 AM · Mon, Thu'), findsOneWidget);
    expect(find.text("Today's reminders"), findsOneWidget, reason: '1 Oct is a Thursday');

    await tester.tap(find.textContaining('11:00 AM · Mon, Thu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Drink 2 glasses of water');
    await tester.scrollUntilVisible(find.text('Save changes'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(s.customRemindersOf(s.selfPatientId!).single.title, 'Drink 2 glasses of water');

    await tester.tap(find.textContaining('11:00 AM · Mon, Thu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(SlabButton, 'Delete'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(SlabButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(s.customRemindersOf(s.selfPatientId!), isEmpty);
    expect(find.text('Create a reminder'), findsOneWidget);
  });
}
