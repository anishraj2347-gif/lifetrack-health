import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ai/insight.dart';
import 'package:lifetrack/src/ai/plane_a/banned_phrases.dart';
import 'package:lifetrack/src/ai/plane_a/deterministic_insights.dart';
import 'package:lifetrack/src/ai/plane_a/reference_ranges.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';

void main() {
  final at = DateTime(2026, 4, 1);
  final adultWoman = Patient(id: 'p1', name: 'Test Patient', dateOfBirth: DateTime(1984, 6, 14), sex: Sex.female);

  HealthRecord report(String id, DateTime date, List<LabResult> results) => HealthRecord(
        id: id,
        patientId: 'p1',
        kind: RecordKind.report,
        title: 'Report',
        date: date,
        source: RecordSource.doctorIssued,
        results: results,
      );

  InsightRun runOne(String analyte, double value, String unit, {Patient? patient}) => DeterministicInsights.run(
        patient: patient ?? adultWoman,
        records: [report('r1', DateTime(2026, 3, 9), [LabResult(analyte: analyte, value: value, unit: unit)])],
        at: at,
      );

  group('range comparison', () {
    test('a value above range is a discuss-soon finding that states position and stops', () {
      final run = runOne('ldl', 132, 'mg/dL');
      final i = run.insights.single;
      expect(i.severity, Severity.discussSoon);
      expect(i.finding, contains('above the reference range of 99 mg/dL or below'));
      expect(i.evidence, ['r1']);
    });

    test('a unit mismatch is not checked — never out of range', () {
      // 12 mmol/L is genuinely high (216 mg/dL). Compared naively against
      // 70–99 mg/dL it would read as catastrophic hypoglycaemia.
      final run = runOne('glucose_fasting', 12, 'mmol/L');
      expect(run.insights, isEmpty);
      expect(run.unresolved.single.reason, NotCheckedReason.unitMismatch);
      expect(run.allChecked, isFalse);
    });

    test('an analyte with no range is reported as not checked', () {
      final run = runOne('vitamin_d', 18, 'ng/mL');
      expect(run.unresolved.single.reason, NotCheckedReason.noRangeForAnalyte);
    });

    test('adult intervals are not applied to a child', () {
      final child = Patient(id: 'c', name: 'Child', dateOfBirth: DateTime(2020, 1, 1), sex: Sex.male);
      final run = runOne('haemoglobin', 10, 'g/dL', patient: child);
      expect(run.insights, isEmpty);
      expect(run.unresolved.single.reason, NotCheckedReason.notApplicableToPatient);
    });

    test('pregnancy-sensitive intervals are not applied in pregnancy', () {
      final pregnant = Patient(id: 'p', name: 'X', dateOfBirth: DateTime(1990), sex: Sex.female, pregnant: true);
      expect(runOne('haemoglobin', 11, 'g/dL', patient: pregnant).unresolved.single.reason, NotCheckedReason.notApplicableToPatient);
    });
  });

  group('open-ended intervals', () {
    test('describe never prints a sentinel', () {
      final hdl = referenceRanges.firstWhere((r) => r.analyte == 'hdl' && r.sex == Sex.female);
      expect(hdl.describe(), '50 mg/dL or above');
      for (final r in referenceRanges) {
        expect(r.describe(), isNot(contains('999')));
        expect(r.low == 999 || r.high == 999, isFalse);
      }
    });
  });

  group('critical values — three levels, severity and action only', () {
    test('below range but above critical is discuss soon', () {
      expect(runOne('glucose_fasting', 60, 'mg/dL').insights.single.severity, Severity.discussSoon);
    });
    test('first critical tier is contact your doctor today', () {
      expect(runOne('glucose_fasting', 50, 'mg/dL').insights.single.severity, Severity.contactDoctorToday);
    });
    test('second critical tier is urgent care', () {
      final i = runOne('haemoglobin', 6.5, 'g/dL').insights.single;
      expect(i.severity, Severity.urgentCare);
      expect(i.action, contains('108'));
    });
    test('escalation does not change the finding wording', () {
      final mild = runOne('glucose_fasting', 60, 'mg/dL').insights.single.finding;
      final severe = runOne('glucose_fasting', 35, 'mg/dL').insights.single.finding;
      expect(severe.replaceAll('35', '60'), mild);
    });
  });

  group('trends are direction- and endpoint-aware', () {
    test('an improving HbA1c is a note, never red', () {
      final run = DeterministicInsights.run(patient: adultWoman, at: at, records: [
        report('a', DateTime(2025, 7, 2), const [LabResult(analyte: 'hba1c', value: 6.8, unit: '%')]),
        report('b', DateTime(2026, 1, 5), const [LabResult(analyte: 'hba1c', value: 6.1, unit: '%')]),
      ]);
      final trend = run.insights.firstWhere((i) => i.kind == InsightKind.trend);
      expect(trend.severity, Severity.note);
    });

    test('a falling haemoglobin that leaves the range is raised', () {
      final run = DeterministicInsights.run(patient: adultWoman, at: at, records: [
        report('a', DateTime(2025, 6, 1), const [LabResult(analyte: 'haemoglobin', value: 13.0, unit: 'g/dL')]),
        report('b', DateTime(2026, 2, 1), const [LabResult(analyte: 'haemoglobin', value: 11.5, unit: 'g/dL')]),
      ]);
      final trend = run.insights.firstWhere((i) => i.kind == InsightKind.trend);
      expect(trend.severity, Severity.discussSoon);
      expect(trend.evidence, ['a', 'b']);
    });

    test('a creatinine rise of 0.3 mg/dL is a trend', () {
      final run = DeterministicInsights.run(patient: adultWoman, at: at, records: [
        report('a', DateTime(2025, 6, 1), const [LabResult(analyte: 'creatinine', value: 0.7, unit: 'mg/dL')]),
        report('b', DateTime(2026, 2, 1), const [LabResult(analyte: 'creatinine', value: 1.0, unit: 'mg/dL')]),
      ]);
      expect(run.insights.where((i) => i.kind == InsightKind.trend), hasLength(1));
    });
  });

  test('two prescriptions for one ingredient from different doctors are flagged', () {
    final run = DeterministicInsights.run(patient: DemoData.patient('p1'), records: DemoData.records('p1'), at: at);
    final med = run.insights.singleWhere((i) => i.kind == InsightKind.medication);
    expect(med.finding, contains('metformin'));
    expect(med.evidence, hasLength(2));
  });

  group('banned phrases', () {
    test('nothing the engine emits on the demo set is banned, and nothing was dropped', () {
      final run = DeterministicInsights.run(patient: DemoData.patient('p1'), records: DemoData.records('p1'), at: at);
      expect(run.dropped, 0);
      for (final i in run.insights) {
        expect(firstBannedPhrase(i.finding), isNull, reason: i.finding);
        expect(firstBannedPhrase(i.action), isNull, reason: i.action);
      }
      expect(firstBannedPhrase(Insight.disclaimer), isNull);
    });

    test('the filter catches hedged forecasts as well as assertions', () {
      for (final s in [
        'You have diabetes.',
        'This may indicate early kidney disease.',
        'Consistent with prediabetes.',
        'Elevated risk of progression to type 2.',
        'A 30% probability of a cardiac event.',
      ]) {
        expect(firstBannedPhrase(s), isNotNull, reason: s);
      }
    });
  });
}
