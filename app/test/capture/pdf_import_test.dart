import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/capture/report_image.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/share_bundle.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/widgets/summary_view.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  test('a PDF page (rendered to PNG) goes through the same clean step as a photo', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 1240, height: 1754)..clear(img.ColorRgb8(255, 255, 255))));
    final page = await ReportImage.prepare(png);
    expect(page[0], 0xFF, reason: 'stored as JPEG');
    expect(page[1], 0xD8);
    expect(img.decodeJpg(page)!.height, lessThanOrEqualTo(1800));
  });

  test('a report from a PDF says so, on the phone and to the doctor', () async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 3)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => DateTime(2026, 10, 1),
    );
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 800, height: 1100)));
    await s.addScanned(
      rawPages: [png, png],
      draft: HealthRecord(
        id: 'r1', patientId: s.selfPatientId!, kind: RecordKind.report, title: 'Thyroid profile', date: DateTime(2026, 9, 28),
        source: RecordSource.smartCapture, originalFormat: 'pdf', labName: 'Dr Lal PathLabs',
        results: const [LabResult(analyte: 'tsh', value: 3.1, unit: 'mIU/L')],
      ),
    );
    final r = s.records().single;
    expect((r.originalFormat, r.provenance), ('pdf', Provenance.photoOfReport));
    expect(await s.attachments.load(r.attachmentId!), hasLength(2));
    expect(HealthRecord.fromJson(r.toJson()).originalFormat, 'pdf');

    final test = ShareBundle.latestTestsForTest([r], DateTime(2026, 10, 1)).single;
    expect(test['original'], 'pdf');
    expect(SummaryView.sourceBadge(test['source']! as String, test['original'] as String?).$1, 'PDF of report');
  });
}
