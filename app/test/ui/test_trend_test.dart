import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/screens/record_screen.dart';
import 'package:lifetrack/src/ui/screens/test_trend_screen.dart';
import 'package:lifetrack/src/ui/widgets/trend_card.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10);

  HealthRecord report(String id, String pid, DateTime d, List<LabResult> results, {String lab = 'SRL Diagnostics'}) => HealthRecord(
        id: id, patientId: pid, kind: RecordKind.report, title: 'Report $id', date: d, source: RecordSource.typedByPatient,
        labName: lab, doctor: 'Dr. Mehta', results: results,
      );
  LabResult a1c(double v) => LabResult(analyte: 'hba1c', value: v, unit: '%');
  LabResult ldl(double v) => LabResult(analyte: 'ldl', value: v, unit: 'mg/dL');
  LabResult fbs(double v) => LabResult(analyte: 'glucose_fasting', value: v, unit: 'mg/dL');

  List<HealthRecord> sample(String pid) => [
        report('1', pid, DateTime(2025, 7, 2), [a1c(6.8), ldl(150), fbs(120)]),
        report('2', pid, DateTime(2026, 1, 10), [a1c(6.4), ldl(132)]),
        report('3', pid, DateTime(2026, 9, 8), [a1c(6.1), fbs(104)], lab: 'Thyrocare'),
        report('4', pid, DateTime(2026, 9, 20), [ldl(118)]),
      ];

  test('a trend for every test with more than two results, latest measured first', () {
    final t = TrendCard.all(sample('p'));
    expect(t.map((x) => x.analyte), ['ldl', 'hba1c'], reason: 'fasting glucose has only two');
    expect(t.first.points.map((p) => p.$2.value), [150, 132, 118], reason: 'oldest first');
  });

  testWidgets('Records shows them; tapping opens every result with date, lab and report', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 8)), remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
      );
      final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      for (final r in sample(me.id)) {
        await s.addRecord(r);
      }
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Records'));
    await tester.pumpAndSettle();

    expect(find.byType(TrendCard), findsOneWidget);
    expect(find.byType(MoreTrends), findsOneWidget);
    expect(find.textContaining('tap for every result'), findsOneWidget);

    await tester.tap(find.text('HbA1c'));
    await tester.pumpAndSettle();
    expect(find.byType(TestTrendScreen), findsOneWidget);
    expect(find.text('Open report'), findsNWidgets(2), reason: 'two on screen; the third is below');
    expect(find.textContaining('8 Sep 2026 · Thyrocare · Dr: Dr. Mehta'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('3 weeks ago'), findsOneWidget);

    await tester.tap(find.text('Open report').first);
    await tester.pumpAndSettle();
    expect(find.byType(RecordScreen), findsOneWidget);
    expect(find.text('Report 3'), findsWidgets);
  });
}
