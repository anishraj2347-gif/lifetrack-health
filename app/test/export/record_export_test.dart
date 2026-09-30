import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  var now = DateTime(2026, 10, 1, 10);

  Future<AppServices> open() async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 7)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
    );
    await s.createProfile(name: 'Anjali <Sharma>', dob: DateTime(1984), sex: Sex.female);
    return s;
  }

  test('one zip: a readable page, the same records as JSON, and the access log — logged first', () async {
    final s = await open();
    final id = s.selfPatientId!;
    await s.emergency.save(id, const EmergencyCard(bloodType: 'B+'));
    await s.addRecord(HealthRecord(
      id: 'r1',
      patientId: id,
      kind: RecordKind.report,
      title: 'Lipid panel',
      date: DateTime(2026, 3, 9),
      source: RecordSource.smartCapture,
      labName: 'Apollo',
      results: const [LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL', printedHigh: 100)],
    ));

    final e = await s.exportCurrent();
    expect(s.audit.entriesFor(id).first.action, AuditAction.export, reason: "newest first");
    final zip = ZipDecoder().decodeBytes(e.zip());
    expect(zip.files.map((f) => f.name), containsAll(['records.json', 'summary.html']));

    final j = jsonDecode(utf8.decode(zip.findFile('records.json')!.content as List<int>)) as Map;
    expect(j['format'], 'lifetrack-export');
    expect((j['records'] as List).single['title'], 'Lipid panel');
    expect((j['emergencyId'] as Map)['blood'], 'B+');
    expect((j['accessLog'] as List).any((a) => (a as Map)['action'] == 'export'), isTrue);

    final html = utf8.decode(zip.findFile('summary.html')!.content as List<int>);
    expect(html, contains('Anjali &lt;Sharma&gt;'), reason: 'names are escaped, never markup');
    expect(html, isNot(contains('<Sharma>')));
    expect(html, contains('132 mg/dL'));
    expect(html, contains('not encrypted'));
    expect(html, contains('lab range 100 or below'));
    expect(html, contains('typed in by the patient'));
    for (final w in ['abnormal', 'normal', 'above the', 'below the', 'out of range', 'high', 'low ']) {
      expect(html.toLowerCase(), isNot(contains(w)), reason: 'the export copies values; it does not judge them ("$w")');
    }
    expect(e.fileName, 'lifetrack-anjali-sharma-2026-10-01.zip');
  });

  test("a parent can export a child's records, but not after the child turns 18", () async {
    final s = await open();
    final child = await s.addChild(name: 'Riya', dob: DateTime(2008, 10, 15), sex: Sex.female, relation: 'daughter');
    await s.switchTo(child.id);
    await s.exportCurrent();
    now = DateTime(2026, 10, 16);
    await expectLater(s.exportCurrent(), throwsA(isA<CustodyRefused>()));
    now = DateTime(2026, 10, 1, 10);
  });
}
