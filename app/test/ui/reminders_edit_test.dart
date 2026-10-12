import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/reminders/custom_reminder.dart';
import 'package:lifetrack/src/reminders/reminder_plan.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/custom_reminder_screen.dart';
import 'package:lifetrack/src/ui/screens/reminders_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Today's and coming-up reminders open for editing from where they are shown.
void main() {
  final now = DateTime(2026, 10, 12, 7);
  late AppServices s;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: Scaffold(body: RemindersTab()))));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 6)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
    );
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.addRecord(HealthRecord(
      id: 'rx1', patientId: me.id, kind: RecordKind.prescription, title: 'Metformin 500 mg', date: DateTime(2026, 10, 1),
      source: RecordSource.typedByPatient, dose: const Dose(morning: 1, afternoon: 0, night: 0), ingredient: 'metformin',
    ));
    await s.saveCustomReminder(CustomReminder(id: 'c1', patientId: me.id, title: 'Check blood pressure', times: const [(9, 30)], start: DateTime(2026, 10, 1)));
  });

  testWidgets("a reminder in today's list opens to be edited", (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Edit Check blood pressure'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomReminderScreen), findsOneWidget);
  });

  testWidgets("tapping a dose time in today's medicines changes it for that slot", (tester) async {
    await show(tester);
    await tester.tap(find.descendant(of: find.byType(TodaysMedicines), matching: find.textContaining('Morning ·')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(s.reminderSettings.times[DoseSlot.morning], isNotNull);
  });

  testWidgets('a coming-up reminder opens what it is about', (tester) async {
    s.settings['reminders'] = const ReminderSettings(on: true).toJson();
    await show(tester);
    final row = find.text('Check blood pressure').last;
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(CustomReminderScreen), findsOneWidget);
  });
}
