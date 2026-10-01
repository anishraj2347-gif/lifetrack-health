import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10);

  Future<AppServices> open() async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 6)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
    );
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    return s;
  }

  HealthRecord rx(String patientId, {RecordSource source = RecordSource.typedByPatient}) => HealthRecord(
        id: 'rx1',
        patientId: patientId,
        kind: RecordKind.prescription,
        title: 'Telmisartan 40 mg',
        date: now,
        source: source,
        doctor: 'Dr. S. IyerFortis',
        dose: const Dose(morning: 1, afternoon: 0, night: 1),
      );

  test('a typed record is corrected in place, and the correction is logged', () async {
    final s = await open();
    await s.addRecord(rx(s.selfPatientId!));
    final r = s.records().single;
    final fixed = HealthRecord(id: r.id, patientId: r.patientId, kind: r.kind, title: r.title, date: r.date, source: r.source, doctor: 'Dr. S. Iyer', facility: 'Fortis', dose: r.dose);
    await s.updateRecord(fixed);
    expect(s.records().single.doctor, 'Dr. S. Iyer');
    expect(s.records().single.facility, 'Fortis');
    expect(s.records(), hasLength(1));
    expect(s.audit.entriesFor(s.selfPatientId!).first.detail, contains('corrected "Telmisartan 40 mg"'));
  });

  test('a signed record cannot be changed, only removed', () async {
    final s = await open();
    await s.addRecord(rx(s.selfPatientId!, source: RecordSource.doctorIssued));
    final r = s.records().single;
    expect(r.editable, isFalse);
    await expectLater(s.updateRecord(r), throwsStateError);
    await s.deleteRecord(r);
    expect(s.records(), isEmpty);
  });

  test('deleting removes the original pages too, and is logged', () async {
    final s = await open();
    await s.attachments.save('a1', [Uint8List.fromList([1, 2, 3])]);
    final r = HealthRecord(id: 'r9', patientId: s.selfPatientId!, kind: RecordKind.report, title: 'Lipid panel', date: now, source: RecordSource.smartCapture, attachmentId: 'a1');
    await s.addRecord(r);
    await s.deleteRecord(r);
    expect(await s.attachments.load('a1'), isEmpty);
    final log = s.audit.entriesFor(s.selfPatientId!).first;
    expect((log.action, log.detail), (AuditAction.edit, 'deleted "Lipid panel"'));
  });

  testWidgets('Edit from the record screen corrects the doctor; Delete removes it', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await open();
      await s.addRecord(rx(s.selfPatientId!));
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telmisartan 40 mg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Correct it'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Dr. S. IyerFortis'), 'Dr. S. Iyer');
    await tester.dragUntilVisible(find.text('Save record'), find.ancestor(of: find.text('Correct it'), matching: find.byType(Scrollable)).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(s.records().single.doctor, 'Dr. S. Iyer');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(s.records(), isEmpty);
    expect(find.text('No records yet'), findsOneWidget);
  });
}
