import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lifetrack/src/ai/plane_b/capture.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/capture/tesseract_reader.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/scan_report_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

import 'ocr_fixture.dart';

class _FakeReader implements PageReader {
  _FakeReader(this.page);
  final OcrPage page;
  int reads = 0;
  @override
  Future<OcrPage> read(Uint8List p) async {
    reads++;
    return page;
  }
}

Future<AppServices> _open({PageReader? reader}) async {
  final s = await AppServices.open(
    bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 5)), remote: InMemoryRemoteVaultStore(),
    kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => DateTime(2026, 10, 2, 10), pageReader: reader,
  );
  await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
  return s;
}

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 600, height: 800)..clear(img.ColorRgb8(255, 255, 255))));

void main() {
  group('saving what was scanned', () {
    test('a prescription with two medicines is two records on one set of pages', () async {
      final s = await _open();
      final me = s.selfPatientId!;
      HealthRecord rx(String id, String title) =>
          HealthRecord(id: id, patientId: me, kind: RecordKind.prescription, title: title, date: DateTime(2026, 9, 30), source: RecordSource.smartCapture, dose: const Dose(morning: 1, afternoon: 0, night: 1));
      final saved = await s.addScannedAll(drafts: [rx('a', 'Metformin 500 mg'), rx('b', 'Atorvastatin 10 mg')], rawPages: [_png], checked: 'from a scan, checked by the patient against the photo (1 of 3 highlighted or edited items changed)');
      expect(saved.map((r) => r.attachmentId).toSet(), hasLength(1));
      expect(s.records().map((r) => r.provenance), everyElement(Provenance.photoOfReport));

      final log = s.audit.entriesFor(me).where((e) => e.action == AuditAction.edit && (e.detail ?? '').contains('from a scan')).toList();
      expect(log, hasLength(2), reason: 'every record added is in the access log (#13)');

      // Removing one medicine keeps the pages the other still points to.
      await s.deleteRecord(saved.first);
      expect(await s.originals(saved.last), hasLength(1));
      await s.deleteRecord(saved.last);
      expect(await s.attachments.pageCount(saved.last.attachmentId!), 0);
    });
  });

  group('the review screen', () {
    Future<_FakeReader> pump(WidgetTester tester, List<String> rows, {double conf = 93}) async {
      // Tall enough that the whole review is built and every badge counted.
      tester.view.physicalSize = const Size(1080, 12000);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final reader = _FakeReader(page(rows, conf: conf));
      final s = await tester.runAsync(() => _open(reader: reader));
      await tester.pumpWidget(AppScope(
        services: s!,
        child: MaterialApp(theme: LT.theme(), home: ScanReportScreen(incoming: [(mime: 'image/png', bytes: _png)])),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read 1 page'));
      await tester.pumpAndSettle();
      return reader;
    }

    Finder field(String text) => find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);
    SlabButton slab(String label) => find.widgetWithText(SlabButton, label).evaluate().single.widget as SlabButton;
    bool enabled(String label) => slab(label).onPressed != null;

    testWidgets('a clean print: fields filled, one confirm saves', (tester) async {
      final reader = await pump(tester, [
        'Thyrocare',
        'Ref. By : Dr. Meera Iyer | Sample Collected : 25/09/2026',
        'THYROID PROFILE',
        'TSH | 3.1 | µIU/mL | 0.4 - 4.0',
      ]);
      expect(reader.reads, 1);
      expect(find.text('Is this what it says?'), findsOneWidget);
      expect(find.text('Check this'), findsNothing);
      expect(field('Thyrocare'), findsOneWidget);
      expect(find.text('25 Sep 2026'), findsOneWidget);
      expect(enabled('This matches my report'), isTrue);
    });

    testWidgets('unsure items hold the save until each is ticked or corrected', (tester) async {
      await pump(tester, [
        'City Diagnostics Laboratory',
        'Collected 25/09/2026',
        'Haemoglobin | 13.2 | g/dL | 12.0 - 15.0',
        'Fasting Blood Sugar | 92 | mg/dL | 70 - 100',
      ], conf: 78);
      final waiting = find.text('Check this');
      expect(waiting, findsWidgets);
      final n = waiting.evaluate().length;
      final label = 'Check $n highlighted item${n == 1 ? '' : 's'} first';
      expect(enabled(label), isFalse);

      // Ticking every "Matches the photo" releases it.
      // Each highlighted item has one "Matches the photo" tick.
      final ticks = find.byType(Checkbox);
      expect(ticks.evaluate().length, n);
      for (var i = 0; i < n; i++) {
        await tester.ensureVisible(ticks.at(i));
        await tester.pumpAndSettle();
        await tester.tap(ticks.at(i));
        await tester.pumpAndSettle();
        if (i < n - 1) expect(enabled('Check ${n - i - 1} highlighted item${n - i - 1 == 1 ? '' : 's'} first'), isFalse);
      }
      expect(find.text('Check this'), findsNothing);
      expect(enabled('This matches my report'), isTrue);
    });

    testWidgets('handwriting is flagged and nothing is trusted unticked', (tester) async {
      await pump(tester, ['Dr. Sharma', 'Rx', 'Tab Pantop 40 1-0-0 before food'], conf: 45);
      expect(find.text('This looks handwritten'), findsOneWidget);
      expect(field('Pantop 40'), findsOneWidget);
      expect(find.text('Check this'), findsWidgets);
    });

    testWidgets('nothing read: the plain form, and the patient types it in', (tester) async {
      await pump(tester, []);
      expect(find.text('What is it?'), findsOneWidget);
      expect(find.textContaining('could not read this page'), findsOneWidget);
      expect(find.text('Check this'), findsNothing);
    });
  });

  test('pages go to Tesseract as grey pixels, upright and about 2200 px', () {
    final g = greyForOcr(Uint8List.fromList(img.encodePng(img.Image(width: 3000, height: 4000)..clear(img.ColorRgb8(255, 255, 255)))));
    expect(g.height, 2200);
    expect(g.width, 1650);
    expect(g.pixels.length, g.width * g.height, reason: 'one byte per pixel');
    expect(g.pixels.first, 255);
  });
}
