import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ai/insight.dart';
import 'package:lifetrack/src/ai/plane_a/banned_phrases.dart';
import 'package:lifetrack/src/ai/plane_a/critical_check.dart';
import 'package:lifetrack/src/ai/plane_a/critical_values.dart';
import 'package:lifetrack/src/ai/plane_a/deterministic_insights.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final at = DateTime(2026, 11, 6, 9);
  final woman = Patient(id: 'p1', name: 'A', dateOfBirth: DateTime(1984, 6, 14), sex: Sex.female);
  final man = Patient(id: 'p2', name: 'B', dateOfBirth: DateTime(1960, 1, 1), sex: Sex.male);
  final child = Patient(id: 'c', name: 'C', dateOfBirth: DateTime(2020, 1, 1), sex: Sex.male);
  final baby = Patient(id: 'b', name: 'D', dateOfBirth: DateTime(2026, 9, 1), sex: Sex.female);
  final pregnant = Patient(id: 'q', name: 'E', dateOfBirth: DateTime(1994, 1, 1), sex: Sex.female, pregnant: true);
  final unspecified = Patient(id: 'u', name: 'F', dateOfBirth: DateTime(1990, 1, 1), sex: Sex.unspecified);

  HealthRecord report(List<LabResult> results, {DateTime? date}) => HealthRecord(id: 'r1', patientId: 'p1', kind: RecordKind.report, title: 'Report', date: date ?? DateTime(2026, 11, 5), source: RecordSource.typedByPatient, results: results);

  InsightRun check(String analyte, double value, String unit, {Patient? who, double? low, double? high}) =>
      CriticalCheck.record(patient: who ?? woman, record: report([LabResult(analyte: analyte, value: value, unit: unit, printedLow: low, printedHigh: high)]), at: at);

  Severity? sev(String analyte, double value, String unit, {Patient? who}) => check(analyte, value, unit, who: who).insights.firstOrNull?.severity;

  group('the values the clinical review found missed', () {
    for (final (analyte, value, unit) in const [
      ('potassium', 6.5, 'mmol/L'),
      ('potassium', 6.5, 'mEq/L'),
      ('sodium', 118.0, 'mmol/L'),
      ('glucose_random', 40.0, 'mg/dL'),
      ('glucose_random', 520.0, 'mg/dL'),
      ('platelets', 8000.0, '/cumm'),
      ('glucose_fasting', 40.0, 'mg/dL'),
    ]) {
      test('$analyte $value $unit is urgent', () {
        final i = check(analyte, value, unit).insights.single;
        expect(i.severity, Severity.urgentCare);
        expect(i.kind, InsightKind.critical);
        expect(i.action, contains('108'));
      });
    }

    test('Hb 5 is urgent for a child, in pregnancy, as gm%, with no unit, and with sex unspecified', () {
      expect(sev('haemoglobin', 5, 'g/dL', who: child), Severity.urgentCare);
      expect(sev('haemoglobin', 5, 'g/dL', who: pregnant), Severity.urgentCare);
      expect(sev('haemoglobin', 5, 'gm%'), Severity.urgentCare);
      expect(sev('haemoglobin', 5, 'gm %'), Severity.urgentCare);
      expect(sev('haemoglobin', 5, ''), Severity.urgentCare);
      expect(sev('haemoglobin', 5, 'g/dL', who: unspecified), Severity.urgentCare);
      expect(sev('haemoglobin', 5, 'g/dL', who: man), Severity.urgentCare);
    });

    test('every glucose below 54 mg/dL is urgent, whatever kind it is', () {
      for (final key in ['glucose', 'glucose_fasting', 'glucose_pp', 'glucose_random']) {
        expect(sev(key, 53.9, 'mg/dL'), Severity.urgentCare, reason: key);
        expect(sev(key, 54, 'mg/dL'), isNull, reason: key);
        expect(sev(key, 2.2, 'mmol/L'), Severity.urgentCare, reason: '$key 2.2 mmol/L is about 40 mg/dL');
        expect(sev(key, 28.9, 'mmol/L'), Severity.urgentCare, reason: '$key 28.9 mmol/L is about 520 mg/dL');
      }
    });
  });

  group('units are normalised first', () {
    test('platelets in every way labs print them', () {
      for (final (v, u) in const [(8000.0, '/µL'), (8000.0, 'cells/cumm'), (8000.0, '/mm³'), (8.0, '10³/µL'), (8.0, 'x10^3/uL'), (8.0, '10^9/L'), (0.08, 'lakh/cumm'), (0.08, 'Lakhs/cumm')]) {
        expect(sev('platelets', v, u), Severity.urgentCare, reason: '$v $u');
      }
      expect(sev('platelets', 1.5, 'lakh/cumm'), isNull);
      expect(sev('platelets', 150000, '/cumm'), isNull);
    });

    test('white cells, calcium, sodium and potassium are covered', () {
      expect(sev('wbc', 800, '/cumm'), Severity.urgentCare);
      expect(sev('wbc', 0.8, '10³/µL'), Severity.urgentCare);
      expect(sev('wbc', 60000, '/µL'), Severity.urgentCare);
      expect(sev('wbc', 7000, '/cumm'), isNull);
      expect(sev('calcium', 6, 'mg/dL'), Severity.urgentCare);
      expect(sev('calcium', 1.4, 'mmol/L'), Severity.urgentCare, reason: 'about 5.6 mg/dL');
      expect(sev('calcium', 14, 'mg/dL'), Severity.urgentCare);
      expect(sev('calcium', 9.5, 'mg/dL'), isNull);
      expect(sev('sodium', 165, 'mEq/L'), Severity.urgentCare);
      expect(sev('sodium', 140, 'mmol/L'), isNull);
      expect(sev('potassium', 2.4, 'mmol/L'), Severity.urgentCare);
      expect(sev('potassium', 5.8, 'mmol/L'), Severity.contactDoctorToday);
      expect(sev('potassium', 4.2, 'mmol/L'), isNull);
    });

    test('a converted value says what it converted to', () {
      expect(check('glucose_random', 2.2, 'mmol/L').insights.single.finding, contains('about 39.6 mg/dL'));
    });
  });

  group('when it cannot tell, it never reassures', () {
    test('no unit: the number is read every way it could be real, and the worst stands', () {
      final i = check('platelets', 8, '').insights.single;
      expect(i.severity, Severity.urgentCare);
      expect(i.finding, contains('no unit on the report'));
      expect(check('glucose_random', 40, '').insights.single.severity, Severity.urgentCare);
    });

    test('an unknown unit is handled like a missing one', () {
      expect(check('potassium', 6.5, 'bananas').insights.single.finding, contains('not recognised'));
    });

    test('a covered value that cannot be judged comes back unresolved', () {
      final run = check('potassium', 65, '');
      expect(run.insights, isEmpty);
      expect(run.unresolved.single.reason, NotCheckedReason.dangerLimitNotChecked);
      expect(run.needsPrompt, isTrue);
    });

    test('a value with no limit crossed produces nothing, not an all-clear', () {
      final run = check('potassium', 4.2, 'mmol/L');
      expect(run.needsPrompt, isFalse);
      expect(run.insights, isEmpty);
    });

    test('a test with no limit stays silent', () {
      expect(check('ldl', 400, 'mg/dL').needsPrompt, isFalse);
    });

    test('a baby is not compared on a high side that is usual at that age (#10)', () {
      final run = check('haemoglobin', 22, 'g/dL', who: baby);
      expect(run.insights, isEmpty);
      expect(run.unresolved.single.reason, NotCheckedReason.dangerLimitNotChecked);
      expect(sev('haemoglobin', 5, 'g/dL', who: baby), Severity.urgentCare, reason: 'the low side still applies');
      expect(sev('potassium', 6.5, 'mmol/L', who: child), Severity.urgentCare);
    });
  });

  group('a unit that brings a banned phrase in with it', () {
    for (final (analyte, value, unit, name) in const [
      ('potassium', 6.8, 'mmol/L risk of', 'Potassium'),
      ('glucose_fasting', 650.0, 'mg/dL is normal', 'Fasting glucose'),
      ('sodium', 110.0, 'you have', 'Sodium'),
      ('platelets', 8000.0, 'kidney failure', 'Platelets'),
      ('haemoglobin', 4.5, 'likely gm%', 'Haemoglobin'),
    ]) {
      test('$analyte $value "$unit" still raises the urgent alert, without the raw text', () {
        final run = check(analyte, value, unit);
        final i = run.insights.single;
        expect(i.severity, Severity.urgentCare, reason: 'it used to vanish');
        expect(run.dropped, 0);
        expect(run.needsPrompt, isTrue);
        expect(firstBannedPhrase('${i.finding} ${i.action}'), isNull);
        expect(i.finding, isNot(contains(unit)));
        expect(i.finding.toLowerCase(), contains(name.toLowerCase().split(' ').last));
        expect(i.finding, contains('urgent attention'));
        expect(i.action, contains('108'));
      });
    }

    test('an old result stays a same-day alert and still says it is old', () {
      final run = CriticalCheck.record(patient: woman, record: report([const LabResult(analyte: 'potassium', value: 6.8, unit: 'risk of')], date: DateTime(2026, 9, 1)), at: at);
      final i = run.insights.single;
      expect(i.severity, Severity.contactDoctorToday);
      expect(i.finding, contains('attention today'));
      expect(i.finding, contains('more than a week old'));
    });

    test('several at once: each keeps its test, the worst first, and evidence stays', () {
      final run = CriticalCheck.record(
        patient: woman,
        record: report(const [LabResult(analyte: 'potassium', value: 6.8, unit: 'risk of'), LabResult(analyte: 'sodium', value: 110, unit: 'mmol/L')]),
        at: at,
      );
      expect(run.insights, hasLength(2));
      expect(run.insights.every((i) => i.evidence.single == 'r1'), isTrue);
    });

    test('text that cannot be made safe is still dropped and counted', () {
      const bad = Insight(kind: InsightKind.critical, severity: Severity.note, finding: 'You have it.', action: 'Stop taking it.', evidence: [], analyte: 'skip');
      final run = CriticalCheck.finish([bad], const []);
      expect((run.insights.length, run.dropped), (0, 1), reason: 'the test name itself fails the rule, so the fixed wording does too');
    });

    test('a clean alert is left exactly as written', () {
      final run = check('potassium', 6.8, 'mmol/L');
      expect(run.insights.single.finding, contains('6.8 mmol/L'));
    });
  });

  test('wording: every limit, both sides, passes the banned-phrase rule and says nothing is normal', () {
    for (final l in criticalLimits) {
      final canonical = l.forms.first.spellings.first;
      for (final key in l.analytes) {
        for (final bound in [l.urgentBelow, l.urgentAbove, l.todayBelow, l.todayAbove].whereType<double>()) {
          for (final v in [bound * 0.5, bound * 1.5]) {
            for (final unit in [canonical, '', 'bananas']) {
              final run = check(key, v, unit);
              expect(run.dropped, 0, reason: '$key $v $unit');
              for (final i in run.insights) {
                expect(firstBannedPhrase('${i.finding} ${i.action}'), isNull);
                expect('${i.finding} ${i.action}'.toLowerCase(), isNot(contains('normal')));
              }
            }
          }
        }
      }
    }
  });

  test('an old report reaches a person today, not the emergency department', () {
    final old = CriticalCheck.record(patient: woman, at: at, record: report(const [LabResult(analyte: 'potassium', value: 6.5, unit: 'mmol/L')], date: DateTime(2024, 3, 1)));
    expect(old.insights.single.severity, Severity.contactDoctorToday);
    expect(old.insights.single.finding, contains('more than a week old'));
  });

  group('the range does not decide', () {
    InsightRun insights(LabResult r, Patient who) => DeterministicInsights.run(patient: who, records: [report([r])], at: at);

    test('a printed range that passes does not hide a danger value', () {
      final run = insights(const LabResult(analyte: 'potassium', value: 6.5, unit: 'mmol/L', printedLow: 3.5, printedHigh: 7), woman);
      expect(run.insights.single.severity, Severity.urgentCare);
    });

    test('a test with no table range is raised, not "not checked"', () {
      final run = insights(const LabResult(analyte: 'sodium', value: 118, unit: 'mmol/L'), woman);
      expect(run.insights.single.severity, Severity.urgentCare);
      expect(run.unresolved, isEmpty);
    });

    test('a printed range that fails takes its severity from the limit', () {
      final run = insights(const LabResult(analyte: 'platelets', value: 8000, unit: '/cumm', printedLow: 150000, printedHigh: 450000), woman);
      expect(run.insights.single.severity, Severity.urgentCare);
      expect(run.insights.single.finding, contains("lab's printed range"));
    });

    test('a child gets the danger finding and no adult range (#10)', () {
      final run = insights(const LabResult(analyte: 'haemoglobin', value: 5, unit: 'g/dL'), child);
      expect(run.insights.single.severity, Severity.urgentCare);
      expect(run.insights.single.finding, isNot(contains('range')));
      expect(run.unresolved, isEmpty);
    });
  });

  group('at save, with no grant', () {
    Future<AppServices> open() => AppServices.open(
          bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 7)), remote: InMemoryRemoteVaultStore(),
          kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => at,
        );

    test('runs with Insights off, leaves consent alone, and writes no read to the log', () async {
      final s = await open();
      final p = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      expect(s.insightsEnabled(), isFalse);
      final r = HealthRecord(id: 'r9', patientId: p.id, kind: RecordKind.report, title: 'Electrolytes', date: at, source: RecordSource.smartCapture, results: const [LabResult(analyte: 'potassium', value: 6.5, unit: 'mmol/L')]);
      await s.addRecord(r);

      final run = s.criticalCheck(r);
      expect(run.insights.single.severity, Severity.urgentCare);
      expect(s.insightsEnabled(), isFalse, reason: 'no grant was created to do this (#5)');
      expect(s.activeGrants(), isEmpty);
      final log = s.auditEntries();
      expect(log.where((e) => e.action == AuditAction.view || e.action == AuditAction.denied), isEmpty, reason: 'nothing read through RecordAccess');
      expect(log.where((e) => e.actorId.startsWith('agent:')), isEmpty);
      final saved = log.singleWhere((e) => e.detail?.contains('Electrolytes') ?? false);
      expect(saved.detail, contains('danger-level prompt: Potassium'));
      expect(saved.detail, isNot(contains('6.5')), reason: 'the log names the test, not the value');
      expect(saved.actorId, 'patient:${p.id}');
    });

    test('a correction that makes a value dangerous is checked too', () async {
      final s = await open();
      final p = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final r = HealthRecord(id: 'r9', patientId: p.id, kind: RecordKind.report, title: 'Electrolytes', date: at, source: RecordSource.typedByPatient, results: const [LabResult(analyte: 'sodium', value: 138, unit: 'mmol/L')]);
      await s.addRecord(r);
      expect(s.criticalCheck(r).needsPrompt, isFalse);
      final fixed = HealthRecord(id: 'r9', patientId: p.id, kind: RecordKind.report, title: 'Electrolytes', date: at, source: RecordSource.typedByPatient, results: const [LabResult(analyte: 'sodium', value: 118, unit: 'mmol/L')]);
      await s.updateRecord(fixed);
      expect(s.criticalCheck(fixed).insights.single.severity, Severity.urgentCare);
      expect(s.auditEntries().where((e) => (e.detail ?? '').contains('corrected')).single.detail, contains('Sodium'));
    });
  });

  group('a limit, not a number', () {
    LabResult bound(String analyte, double v, String unit, String c) => LabResult(analyte: analyte, value: v, unit: unit, comparator: c);
    InsightRun check1(LabResult r) => CriticalCheck.record(patient: woman, record: report([r]), at: at);

    test('>600 glucose and <20 platelets-in-thousands are urgent, and show the sign', () {
      final i = check1(bound('glucose_random', 600, 'mg/dL', '>')).insights.single;
      expect(i.severity, Severity.urgentCare);
      expect(i.finding, contains('>600 mg/dL'));
      expect(check1(bound('glucose_random', 40, 'mg/dL', '<')).insights.single.severity, Severity.urgentCare);
      expect(check1(bound('potassium', 6, 'mmol/L', '>')).insights.single.severity, Severity.urgentCare, reason: 'past 6 is past the limit');
    });

    test('a limit that could be either side is not checked, never fine', () {
      final open = check1(bound('glucose_random', 100, 'mg/dL', '>'));
      expect(open.insights, isEmpty);
      expect(open.unresolved.single.reason, NotCheckedReason.dangerLimitNotChecked);
      expect(check1(bound('glucose_random', 40, 'mg/dL', '>')).insights, isEmpty);
      expect(check1(bound('hba1c', 5, '%', '<')).needsPrompt, isFalse, reason: 'no limit lies on that side');
    });

    test('against a range: past it is outside, and otherwise not checked', () {
      InsightRun run(LabResult r) => DeterministicInsights.run(patient: woman, records: [report([r])], at: at);
      const past = LabResult(analyte: 'tsh', value: 0.01, unit: 'mIU/L', comparator: '<', printedLow: 0.4, printedHigh: 4);
      expect(run(past).insights.single.finding, allOf(contains('<0.01'), contains('below')));
      const within = LabResult(analyte: 'ldl', value: 50, unit: 'mg/dL', comparator: '<');
      expect(run(within).insights, isEmpty);
      expect(run(within).unresolved, isEmpty, reason: 'below 50 is inside "99 or below"');
      const unknown = LabResult(analyte: 'tsh', value: 2, unit: 'mIU/L', comparator: '>', printedLow: 0.4, printedHigh: 4);
      expect(run(unknown).unresolved.single.reason, NotCheckedReason.reportedAsLimit);
    });

    test('stored, read back, and never a point on a trend', () {
      const r = LabResult(analyte: 'hba1c', value: 14, unit: '%', comparator: '>');
      expect(LabResult.fromJson(r.toJson()).comparator, '>');
      expect(LabResult.parseValue('> 600'), ('>', 600));
      expect(LabResult.parseValue('6.5'), (null, 6.5));
      expect(LabResult.parseValue('≤ 2'), ('<', 2));
      expect(LabResult.parseValue('nil'), isNull);
      final run = DeterministicInsights.run(patient: woman, at: at, records: [
        HealthRecord(id: 'a', patientId: 'p1', kind: RecordKind.report, title: 'A', date: DateTime(2026, 1, 1), source: RecordSource.typedByPatient, results: const [LabResult(analyte: 'hba1c', value: 6, unit: '%')]),
        report(const [r]),
      ]);
      expect(run.insights.where((i) => i.kind == InsightKind.trend), isEmpty);
    });
  });

  group('printed ranges and who they are for (#10)', () {
    InsightRun run(LabResult r, Patient who) => DeterministicInsights.run(patient: who, records: [report([r])], at: at);
    const creatinine = LabResult(analyte: 'creatinine', value: 1.2, unit: 'mg/dL');
    const hb = LabResult(analyte: 'haemoglobin', value: 10, unit: 'g/dL', printedLow: 13, printedHigh: 17);

    test('a woman with no printed band is held to her own table range', () {
      expect(run(creatinine, woman).insights.single.finding, contains('for adult women'));
    });

    test('a printed adult range never reaches a child', () {
      final r = run(hb, child);
      expect(r.insights, isEmpty);
      expect(r.unresolved.single.reason, NotCheckedReason.notApplicableToPatient);
    });

    test('nor a pregnancy, where pregnancy shifts it', () {
      final r = run(hb, pregnant);
      expect(r.insights, isEmpty);
      expect(r.unresolved.single.reason, NotCheckedReason.notApplicableToPatient);
    });

    test('a danger value still shows for them, with no range', () {
      final r = run(const LabResult(analyte: 'haemoglobin', value: 5, unit: 'g/dL', printedLow: 13, printedHigh: 17), child);
      expect(r.insights.single.severity, Severity.urgentCare);
      expect(r.unresolved, isEmpty);
    });
  });

  test('normaliseUnit folds the spellings on real reports', () {
    expect(normaliseUnit(' Gm % '), 'gm%');
    expect(normaliseUnit('x10^3/µL'), '103/ul');
    expect(normaliseUnit('×10³/μL'), '103/ul');
    expect(normaliseUnit('cells/cu.mm'), '/cumm');
  });
}
