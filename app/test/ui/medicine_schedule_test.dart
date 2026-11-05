import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/reminders/reminder_plan.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/add_record_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A weekly medicine typed in by hand must never read as a daily one.
void main() {
  final now = DateTime(2026, 10, 1, 9);
  const somethingElse = 'Something else · weekly or other';

  Future<AppServices> pumpForm(WidgetTester tester, {HealthRecord Function(String patientId)? editing}) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(), kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now);
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      if (editing != null) await s.addRecord(editing(s.selfPatientId!));
    });
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final existing = editing?.call(s.selfPatientId!);
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => AddRecordScreen(editing: existing))), child: const Text('open'))))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (existing == null) {
      await tester.tap(find.text('Type it in'));
      await tester.pumpAndSettle();
    }
    return s;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Save record'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  HealthRecord only(AppServices s) => s.repository.recordsOf(s.selfPatientId!).single;

  testWidgets('a weekly medicine is saved in its own words, with no dose and no reminders', (tester) async {
    final s = await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, 'Methotrexate 15 mg');
    await tapChip(tester, somethingElse);

    await save(tester);
    expect(find.text('Write the dose exactly as prescribed.'), findsOneWidget, reason: 'nothing is assumed');
    expect(s.repository.recordsOf(s.selfPatientId!), isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'As prescribed, e.g. 15 mg once a week on Sunday'), '15 mg once a week on Sunday');
    await save(tester);

    final r = only(s);
    expect(r.dose, isNull);
    expect(r.instructions, '15 mg once a week on Sunday');
    expect(s.todaysDoses(), isEmpty, reason: 'it never appears as a daily dose');
    expect(planReminders(people: [(s.currentPatient!, [r])], settings: const ReminderSettings(on: true), now: now), isEmpty);
  });

  testWidgets('choosing it sets no dose, and turns off "Only when needed"', (tester) async {
    final s = await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, 'Vitamin D3 60000 IU');
    await tapChip(tester, 'Only when needed · no reminders');
    await tapChip(tester, somethingElse);
    await tester.enterText(find.widgetWithText(TextField, 'As prescribed, e.g. 15 mg once a week on Sunday'), 'Once a week for 8 weeks');
    await save(tester);
    expect((only(s).dose, only(s).instructions), (null, 'Once a week for 8 weeks'));
  });

  testWidgets('with no choice made the form still refuses, and names every way out', (tester) async {
    final s = await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, 'Metformin 500 mg');
    await save(tester);
    expect(find.textContaining('"Something else"'), findsWidgets);
    expect(s.repository.recordsOf(s.selfPatientId!), isEmpty, reason: 'no dose is ever defaulted');
  });

  testWidgets('correcting it shows the words again; moving to a daily dose removes them', (tester) async {
    HealthRecord weekly(String id) => HealthRecord(id: 'w1', patientId: id, kind: RecordKind.prescription, title: 'Methotrexate', date: now, source: RecordSource.typedByPatient, instructions: 'Weekly');
    final s = await pumpForm(tester, editing: weekly);
    expect(find.text('Weekly'), findsOneWidget);
    await tapChip(tester, somethingElse);
    // The daily stepper is back in play: one in the morning.
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pump();
    await save(tester);
    expect(only(s).dose?.morning, 1);
    expect(only(s).instructions, isNull);
  });

  testWidgets('an "only when needed" medicine stays one when corrected', (tester) async {
    HealthRecord prn(String id) => HealthRecord(id: 'p1', patientId: id, kind: RecordKind.prescription, title: 'Paracetamol', date: now, source: RecordSource.typedByPatient);
    final s = await pumpForm(tester, editing: prn);
    await save(tester);
    expect((only(s).dose, only(s).instructions), (null, null));
  });
}
