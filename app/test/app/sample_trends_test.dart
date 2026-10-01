import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/app/test_history.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/widgets/trend_card.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  Map<String, int> counts(List<HealthRecord> rs) {
    final c = <String, int>{};
    for (final r in rs) {
      for (final x in r.results) {
        c[x.analyte] = (c[x.analyte] ?? 0) + 1;
      }
    }
    return c;
  }

  group('sample data', () {
    final rs = DemoData.records('p');

    test('has tests with three results and tests with two', () {
      final c = counts(rs);
      expect({for (final e in c.entries) if (e.value == 3) e.key},
          {'hba1c', 'total_cholesterol', 'ldl', 'hdl', 'triglycerides', 'glucose_fasting'});
      expect({for (final e in c.entries) if (e.value == 2) e.key}, {'tsh', 'haemoglobin', 'vitamin_d', 'creatinine'});
      expect(rs.map((r) => r.id).toSet(), hasLength(rs.length), reason: 'ids are unique');
    });

    test('a trend for each test with three, none for two; newest measured first, points oldest first', () {
      final t = TrendCard.all(rs);
      expect(t.map((x) => x.analyte).toSet(), {'hba1c', 'total_cholesterol', 'ldl', 'hdl', 'triglycerides', 'glucose_fasting'});
      expect(t.first.points.last.$1.effectiveDate, DateTime(2026, 9, 22), reason: 'the September lipid panel is the latest');
      for (final s in t) {
        final dates = [for (final p in s.points) p.$1.effectiveDate];
        expect(dates, [...dates]..sort(), reason: '${s.analyte} oldest first');
        expect(s.points, hasLength(3));
      }
      final ldl = t.firstWhere((x) => x.analyte == 'ldl');
      expect(ldl.points.map((p) => p.$2.value), [148, 132, 118]);
      final a1c = t.firstWhere((x) => x.analyte == 'hba1c');
      expect(a1c.points.map((p) => p.$2.value), [6.8, 6.4, 6.1]);
    });

    test('Tests you already have lists the two-result tests too, newest first with the earlier one', () {
      final h = TestHistory(rs);
      final tsh = h.series.firstWhere((s) => s.analyte == 'tsh');
      expect(tsh.points.map((p) => p.$2.value), [2.6, 3.1]);
      expect(tsh.latest.$1.labName, 'Fortis');
      expect(h.series, hasLength(10));
    });
  });

  group('the trend rule', () {
    HealthRecord r(String id, DateTime d, List<LabResult> x) =>
        HealthRecord(id: id, patientId: 'p', kind: RecordKind.report, title: id, date: d, source: RecordSource.typedByPatient, results: x);

    test('exactly two is not enough; a third makes one', () {
      final two = [r('a', DateTime(2026, 1), const [LabResult(analyte: 'tsh', value: 3, unit: 'mIU/L')]), r('b', DateTime(2026, 2), const [LabResult(analyte: 'tsh', value: 2, unit: 'mIU/L')])];
      expect(TrendCard.all(two), isEmpty);
      expect(TrendCard.all([...two, r('c', DateTime(2026, 3), const [LabResult(analyte: 'tsh', value: 2.5, unit: 'mIU/L')])]), hasLength(1));
    });

    test('different units never join one trend', () {
      final mixed = [
        for (var i = 1; i <= 2; i++) r('mg$i', DateTime(2026, i), const [LabResult(analyte: 'glucose_fasting', value: 100, unit: 'mg/dL')]),
        r('mmol', DateTime(2026, 3), const [LabResult(analyte: 'glucose_fasting', value: 5.6, unit: 'mmol/L')]),
      ];
      expect(TrendCard.all(mixed), isEmpty, reason: 'two in mg/dL and one in mmol/L');
    });

    test('ordered by when the sample was taken, not when it was added', () {
      final late = HealthRecord(id: 'x', patientId: 'p', kind: RecordKind.report, title: 'x', date: DateTime(2026, 9, 30), sampleDate: DateTime(2025, 1, 1), source: RecordSource.typedByPatient, results: const [LabResult(analyte: 'hdl', value: 40, unit: 'mg/dL')]);
      final t = TrendCard.all([late, r('y', DateTime(2025, 6), const [LabResult(analyte: 'hdl', value: 45, unit: 'mg/dL')]), r('z', DateTime(2026, 6), const [LabResult(analyte: 'hdl', value: 50, unit: 'mg/dL')])]);
      expect(t.single.points.map((p) => p.$2.value), [40, 45, 50]);
    });
  });

  test('adding the samples twice updates them in place; own records untouched', () async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => DateTime(2026, 10, 1, 10),
    );
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.addRecord(HealthRecord(id: 'mine', patientId: me.id, kind: RecordKind.note, title: 'My note', date: DateTime(2026, 9, 1), source: RecordSource.typedByPatient));
    await s.addSampleRecords();
    final n = s.records().length;
    await s.addSampleRecords();
    expect(s.records(), hasLength(n));
    expect(n, DemoData.records(me.id).length + 1);
    expect(TrendCard.all(s.records()), hasLength(6));
    expect((await s.originals(s.records().firstWhere((r) => r.id == 'demo-thyroid-2025-12'))), hasLength(1), reason: 'each sample report has its stamped photo');
  });
}
