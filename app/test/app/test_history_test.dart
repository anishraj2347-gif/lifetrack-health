import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/test_history.dart';
import 'package:lifetrack/src/model/health_record.dart';

void main() {
  HealthRecord report(String id, DateTime d, List<LabResult> rs, {RecordKind kind = RecordKind.report}) =>
      HealthRecord(id: id, patientId: 'p', kind: kind, title: id, date: d, source: RecordSource.smartCapture, results: rs, labName: 'Thyrocare');

  test('groups each test across reports, newest first; value-less reports and scans listed apart', () {
    final h = TestHistory([
      report('jan', DateTime(2026, 1, 5), const [LabResult(analyte: 'hba1c', value: 6.4, unit: '%')]),
      report('sep', DateTime(2026, 9, 8), const [LabResult(analyte: 'hba1c', value: 6.1, unit: '%')]),
      report('lipid', DateTime(2026, 3, 9), const [LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL'), LabResult(analyte: 'hdl', value: 52, unit: 'mg/dL')]),
      report('xray', DateTime(2026, 1, 18), const [], kind: RecordKind.scan),
      report('thyroid photo', DateTime(2026, 9, 28), const []),
      HealthRecord(id: 'rx', patientId: 'p', kind: RecordKind.prescription, title: 'Metformin', date: DateTime(2026, 9, 1), source: RecordSource.typedByPatient),
    ]);
    expect(h.series.map((s) => s.analyte), ['hba1c', 'ldl', 'hdl']);
    expect(h.series.first.points.map((p) => p.$2.value), [6.1, 6.4]);
    expect(h.documents.map((d) => d.id), ['thyroid photo', 'xray']);
    expect(h.count, 5, reason: 'prescriptions are not tests');
  });

  test('age is stated plainly, never as valid or expired', () {
    expect([ageOf(0), ageOf(1), ageOf(5), ageOf(21), ageOf(120), ageOf(800)], ['today', 'yesterday', '5 days ago', '3 weeks ago', '4 months ago', '2 years ago']);
  });
}
