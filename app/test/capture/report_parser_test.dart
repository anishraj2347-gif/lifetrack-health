import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ai/plane_b/capture.dart';
import 'package:lifetrack/src/ai/plane_b/report_parser.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';

import 'ocr_fixture.dart';

final today = DateTime(2026, 10, 2);

void main() {
  group('a printed lab report', () {
    final lipid = page([
      'Dr Lal PathLabs',
      'National Reference Lab, Sector 18, New Delhi',
      'Name : Mrs. Anjali Sharma | Age : 42 Years',
      'Ref. By : Dr. R K Mehta | Collected : 28/09/2026 08:14',
      'DOB : 12/03/1984 | Reported : 29/09/2026 17:40',
      'LIPID PROFILE',
      'Test Name | Result | Units | Bio. Ref. Interval',
      'Cholesterol, Total | 212 | mg/dL | <200',
      'Triglycerides | 168 | mg/dL | <150',
      'HDL Cholesterol | 44 | mg/dL | >40',
      'LDL Cholesterol | 134.4 | mg/dL | <100',
      'VLDL Cholesterol | 33.6 | mg/dL | <30',
      'Total Cholesterol/HDL Ratio | 4.8 | | 3.5 - 5.0',
      'Fasting Blood Sugar | 104 | mg/dL | 70 - 100',
      'HbA1c (HPLC) | 6.1 | % | 4.0 - 5.6',
    ]);

    test('reads the kind, title, lab, referring doctor and sample date', () {
      final d = parseCapture([lipid], today: today);
      expect(d.kind.value, RecordKind.report);
      expect(d.kind.uncertain, isFalse);
      expect(d.title.value, contains('Lipid panel'));
      expect(d.place.value, 'Dr Lal PathLabs');
      expect(d.doctor.value, 'Dr R K Mehta');
      expect(d.date.value, DateTime(2026, 9, 28), reason: 'the collection date, not the report date or the DOB');
      expect(d.handwriting, isFalse);
    });

    test('joins table columns back into rows and reads value, unit and printed range', () {
      final d = parseCapture([lipid], today: today);
      LabResult r(String k) => d.results.firstWhere((x) => x.value!.analyte == k).value!;
      expect(r('total_cholesterol').value, 212);
      expect(r('total_cholesterol').unit, 'mg/dL');
      expect(r('total_cholesterol').printedHigh, 200);
      expect(r('total_cholesterol').printedLow, isNull, reason: 'an open bound is null (#9a)');
      expect(r('hdl').value, 44);
      expect(r('hdl').printedLow, 40);
      expect(r('ldl').value, 134.4);
      expect(r('vldl').value, 33.6);
      expect(r('triglycerides').value, 168);
      expect(r('glucose_fasting').printedLow, 70);
      expect(r('glucose_fasting').printedHigh, 100);
      expect(r('hba1c').value, 6.1);
      expect(r('hba1c').unit, '%');
      expect(d.results.where((x) => x.value!.analyte == 'hdl'), hasLength(1), reason: 'the ratio row is not HDL');
      expect(d.results.every((x) => !x.uncertain), isTrue);
    });

    test('a tilted photo still lines up', () {
      final tilted = page(['HAEMOGRAM', 'Haemoglobin | 13.2 | g/dL | 12.0 - 15.0', 'Platelet Count | 2,45,000 | /cumm | 1,50,000 - 4,10,000'], dy: 25);
      final d = parseCapture([tilted], today: today);
      expect(d.results.map((r) => (r.value!.analyte, r.value!.value)), containsAll([('haemoglobin', 13.2), ('platelets', 245000.0)]));
      expect(d.title.value, 'Complete blood count');
    });

    test('a misread number is marked for checking, not dropped or "fixed"', () {
      final d = parseCapture([page(['Haemoglobin | 132 | g/dL | 12.0 - 15.0', 'Glucose Fasting | 98 | | 70 - 100'])], today: today);
      final hb = d.results.firstWhere((r) => r.value!.analyte == 'haemoglobin');
      expect(hb.value!.value, 132, reason: 'the draft states what was read');
      expect(hb.uncertain, isTrue);
      final glu = d.results.firstWhere((r) => r.value!.analyte == 'glucose_fasting');
      expect(glu.uncertain, isTrue, reason: 'no unit read');
    });

    test('a low-confidence word is marked for checking', () {
      final d = parseCapture([page(['Serum Creatinine | 0.9 | mg/dL | 0.6 - 1.1'], conf: 70)], today: today);
      expect(d.results.single.uncertain, isTrue);
      expect(d.results.single.seen, contains('0.9'));
    });

    test('a value with a < sign keeps the sign and waits for a tick; the range is not taken for it', () {
      final d = parseCapture([page(['TSH | <0.01 | µIU/mL | 0.4 - 4.0'])], today: today);
      final r = d.results.single;
      expect((r.value!.value, r.value!.comparator, r.uncertain), (0.01, '<', true));
    });
  });

  group('a printed prescription', () {
    final rx = page([
      'Dr. Priya Nair MBBS, MD (Medicine)',
      'Reg. No. 54321 | Sunrise Clinic, Kochi',
      'Date: 30-Sep-2026',
      'Diagnosis: Type 2 diabetes',
      'Rx',
      '1. Tab Metformin 500 mg | 1-0-1 | after food | x 30 days',
      '2. Tab. Atorvastatin 10mg',
      '0-0-1 at bedtime for 1 month',
      '3. Cap Vitamin D3 60000 IU | once a week',
      'Advice: walk 30 minutes daily',
    ]);

    test('one medicine per line, with dose, timing and days', () {
      final d = parseCapture([rx], today: today);
      expect(d.kind.value, RecordKind.prescription);
      expect(d.doctor.value, 'Dr Priya Nair');
      expect(d.date.value, DateTime(2026, 9, 30));
      expect(d.place.value, contains('Clinic'));
      expect(d.medicines, hasLength(3));
      final met = d.medicines[0];
      expect(met.name.value, 'Metformin 500 mg');
      expect((met.dose.value!.morning, met.dose.value!.afternoon, met.dose.value!.night), (1, 0, 1));
      expect(met.timing.value, 'after_food');
      expect(met.days.value, 30);
      final ator = d.medicines[1];
      expect(ator.name.value, 'Atorvastatin 10mg');
      expect((ator.dose.value!.morning, ator.dose.value!.night), (0, 1), reason: 'dose on the line below');
      expect(ator.days.value, 30);
      expect(d.medicines[2].dose.value, isNull, reason: 'weekly has no morning/afternoon/night');
      expect(d.results, isEmpty);
    });

    test('"once a day" does not say when, so the patient picks', () {
      final d = parseCapture([page(['Rx', 'Tab Amlodipine 5 mg OD', 'Tab Telmisartan 40 mg OD'])], today: today);
      expect(d.medicines.first.dose.uncertain, isTrue);
    });
  });

  group('rows that used to vanish', () {
    CaptureDraft read(List<String> rows, {Sex? sex}) => parseCapture([page(['City Pathology Laboratory', 'Test Name | Result | Units | Bio. Ref. Interval', ...rows])], today: today, sex: sex);
    LabResult one(List<String> rows, {Sex? sex}) => read(rows, sex: sex).results.single.value!;

    test('"Glucose" and "Blood Sugar" are read, as glucose of no stated type', () {
      expect(one(['Glucose | 104 | mg/dL | 70 - 140']).analyte, 'glucose');
      expect(one(['Blood Sugar | 240 | mg/dL']).analyte, 'glucose');
      expect(one(['Plasma Glucose | 96 | mg/dL']).analyte, 'glucose');
      expect(one(['Glucose Fasting | 96 | mg/dL']).analyte, 'glucose_fasting', reason: 'a named type still wins');
      expect(one(['Glucose Random | 96 | mg/dL']).analyte, 'glucose_random');
    });

    test('"Hemoglobin A1c 6.5" is HbA1c, not haemoglobin', () {
      for (final row in ['Hemoglobin A1c | 6.5 | %', 'Haemoglobin A1c | 6.5 | %', 'Glycated Hb | 6.5 | %']) {
        final r = one([row]);
        expect((r.analyte, r.value), ('hba1c', 6.5), reason: row);
      }
      expect(one(['Hemoglobin | 13.2 | g/dL']).analyte, 'haemoglobin');
    });

    test('">600" and "<0.01" are kept with their sign, and wait for a tick', () {
      final high = read(['Glucose Random | >600 | mg/dL | 70 - 140']).results.single;
      expect((high.value!.value, high.value!.comparator, high.value!.shownValue), (600, '>', '>600'));
      expect(high.value!.printedHigh, 140);
      expect(high.uncertain, isTrue);
      final low = read(['TSH | <0.01 | µIU/mL | 0.4 - 4.0']).results.single;
      expect((low.value!.value, low.value!.comparator), (0.01, '<'));
      expect(low.uncertain, isTrue);
      expect(one(['TSH | < 0.01 | µIU/mL']).comparator, '<');
      expect(one(['TSH | Less than 0.01 | µIU/mL']).comparator, '<');
    });

    test('a range is never taken for a missing result', () {
      final d = read(['HDL Cholesterol | | mg/dL | >40']);
      expect(d.results, isEmpty);
      expect(d.unread.single, contains('HDL'));
    });

    test('what cannot be read is listed, not dropped', () {
      final d = read(['Serum Phosphorus | 3.5 | mg/dL | 2.5 - 4.5', 'Sodium, Urine | 90 | mmol/L', 'Calcium Ionised | 1.15 | mmol/L', 'Potassium | Haemolysed | mmol/L', 'Glucose Tolerance Test | 180 | mg/dL']);
      expect(d.results, isEmpty, reason: 'none of these is the blood test its first word names');
      expect(d.unread, hasLength(5));
      expect(d.unread.first, contains('Phosphorus'));
    });

    test('a heading is not a row', () {
      expect(read(['HbA1c', 'Haemoglobin | 13.2 | g/dL']).unread, isEmpty);
    });

    test('a danger value always waits for a tick, however clear the print', () {
      expect(read(['Potassium | 6.5 | mmol/L | 3.5 - 5.1']).results.single.uncertain, isTrue);
      expect(read(['Platelet Count | 8000 | /cumm']).results.single.uncertain, isTrue);
      expect(read(['Potassium | 4.2 | mmol/L | 3.5 - 5.1']).results.single.uncertain, isFalse);
    });

    test('a range printed by sex gives the patient their own, or none', () {
      const row = ['Creatinine | 1.2 | mg/dL | Male 0.7-1.3 Female 0.6-1.1'];
      final woman = one(row, sex: Sex.female), man = one(row, sex: Sex.male);
      expect((woman.printedLow, woman.printedHigh), (0.6, 1.1));
      expect((man.printedLow, man.printedHigh), (0.7, 1.3));
      expect(one(row).hasPrintedRange, isFalse, reason: 'sex not known: no band is picked');
      expect(one(row, sex: Sex.unspecified).hasPrintedRange, isFalse);
      expect(one(['Creatinine | 1.2 | mg/dL | Male 0.7-1.3'], sex: Sex.female).hasPrintedRange, isFalse, reason: 'the men\'s band alone is not hers');
      expect(one(['Creatinine | 1.2 | mg/dL | M: 0.7-1.3 F: 0.6-1.1'], sex: Sex.female).printedHigh, 1.1);
    });

    test('a range in bands gives the normal band, or none', () {
      final normal = one(['HbA1c | 6.1 | % | Normal <5.7 Prediabetes 5.7-6.4 Diabetes >=6.5']);
      expect((normal.printedLow, normal.printedHigh), (null, 5.7));
      expect(one(['HbA1c | 6.1 | % | Prediabetes 5.7-6.4']).hasPrintedRange, isFalse);
      expect(one(['HbA1c | 6.1 | % | Prediabetes 5.7-6.4 Diabetes >6.5']).hasPrintedRange, isFalse);
      expect(one(['Cholesterol Total | 212 | mg/dL | Desirable <200 Borderline 200-239 High >=240']).printedHigh, 200);
      expect(one(['LDL Cholesterol | 90 | mg/dL | Optimal <100 Near optimal 100-129']).printedHigh, 100);
      expect(one(['Creatinine | 0.4 | mg/dL | Child 0.3-0.7']).hasPrintedRange, isFalse);
      expect(one(['Creatinine | 0.4 | mg/dL | 0.7-1.3 0.6-1.1']).hasPrintedRange, isFalse, reason: 'two unlabelled ranges: neither is known to apply');
    });

    test('a single plain range is still read, and a High flag does not hide it', () {
      expect(one(['Glucose Fasting | 180 | H | mg/dL | 70 - 100']).printedHigh, 100);
      expect(one(['Glucose Fasting | 180 | High | mg/dL | 70 - 100']).printedHigh, 100);
    });
  });

  group('doses a person must write', () {
    DraftMedicine read(String line, [String? next]) => parseCapture([page(['Rx', line, ?next, 'Advice: review'])], today: today).medicines.single;

    for (final (line, flag) in const [
      ('Tab Methotrexate 15 mg once a week', DoseFlag.notDaily),
      ('Tab Methotrexate 15 mg 1-0-0', DoseFlag.notDaily),
      ('Tab Methotrexate 7.5 mg 1-0-0 weekly', DoseFlag.notDaily),
      ('Tab Folvite 5 mg 1-0-0 on Sunday', DoseFlag.notDaily),
      ('Cap Calcirol 60000 IU every week', DoseFlag.notDaily),
      ('Tab Warfarin 5 mg ½ tablet at night', DoseFlag.fraction),
      ('Tab Warfarin 2 mg 1/2-0-0', DoseFlag.fraction),
      ('Tab Warfarin 2 mg 1-0-0', DoseFlag.fraction),
      ('Tab Ecosprin half tablet after lunch', DoseFlag.fraction),
      ('Tab Tramadol 50 mg SOS', DoseFlag.asNeeded),
      ('Tab Morphine 10 mg 1-0-1 if pain', DoseFlag.asNeeded),
      ('Inj Insulin Glargine 20 units at night', DoseFlag.insulin),
      ('Inj Lantus 12 U 0-0-1', DoseFlag.insulin),
      ('Inj Actrapid 8-0-6', DoseFlag.insulin),
    ]) {
      test('"$line" gets no dose and is flagged', () {
        final m = read(line);
        expect(m.dose.value, isNull);
        expect(m.doseFlag, flag);
      });
    }

    test('a flag on the line below counts', () {
      final m = read('Tab Methotrexate 10 mg', '1-0-0 every week');
      expect((m.dose.value, m.doseFlag), (null, DoseFlag.notDaily));
    });

    test('a course in weeks is a course, not a weekly dose', () {
      final m = read('Tab Amoxicillin 500 mg 1-0-1 for 2 weeks');
      expect(m.doseFlag, isNull);
      expect(m.dose.value!.display, '1-0-1');
      expect(m.days.value, 14);
    });

    test('a page that gives no dose gets none: nothing defaults to 1-0-1', () {
      final m = read('Tab Tramadol 50 mg');
      expect(m.dose.value, isNull);
      expect(m.doseFlag, isNull);
    });
  });

  test('handwriting: whatever is read waits for a tick', () {
    final d = parseCapture([page(['Dr. Sharma', 'Rx', 'Tab Pantop 40 1-0-0 before food', 'Tab Dolo 650 SOS'], conf: 48)], today: today);
    expect(d.handwriting, isTrue);
    expect(d.medicines, isNotEmpty);
    for (final m in d.medicines) {
      expect(m.name.uncertain, isTrue);
    }
    expect(d.kind.uncertain, isTrue);
  });

  test('an X-ray report is a scan, titled by what was imaged', () {
    final d = parseCapture([page(['City Imaging Centre', 'X-RAY CHEST PA VIEW', 'Findings: lung fields are clear', 'Impression: normal study', 'Date 14/08/2026'])], today: today);
    expect(d.kind.value, RecordKind.scan);
    expect(d.title.value, 'X-RAY CHEST PA VIEW');
    expect(d.date.value, DateTime(2026, 8, 14));
  });

  group('dates', () {
    test('day first, every common Indian form', () {
      expect(datesIn('28/09/2026', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('28-09-26', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('28.09.2026', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('28 Sep 2026', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('28th September, 2026', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('Sep 28, 2026', today), [DateTime(2026, 9, 28)]);
      expect(datesIn('2026-09-28', today), [DateTime(2026, 9, 28)]);
    });

    test('no future dates, no impossible dates', () {
      expect(datesIn('05/10/2026', today), isEmpty, reason: '5 Oct is after today');
      expect(datesIn('31/02/2026', today), isEmpty);
    });
  });

  test('nothing readable gives the empty draft', () {
    expect(parseCapture([const OcrPage([])], today: today).readAnything, isFalse);
  });

  test('numbers: Indian grouping, flags', () {
    expect(parseNumber('1,50,000'), 150000);
    expect(parseNumber('150,000'), 150000);
    expect(parseNumber('13.2H'), 13.2);
    expect(parseNumber('4.1*'), 4.1);
    expect(parseNumber('<5'), isNull);
    expect(parseNumber('mg/dL'), isNull);
  });
}
