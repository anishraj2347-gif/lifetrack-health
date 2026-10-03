import 'dart:math';

import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// Demo builds only (`LT_DEMO_TOOLS=true`): made-up patients so the doctor
/// app can be shown without a patient phone. Every name ends in "(sample)".
/// Nothing here comes from or goes to a real person.
const demoTools = bool.fromEnvironment('LT_DEMO_TOOLS');

/// One sample person: who they are, and — for an open share — what they shared.
class SamplePatient {
  const SamplePatient(this.name, this.sex, this.age, {this.share, this.sharedDaysAgo = 0, this.shares = 1});
  final String name;
  final String sex;
  final int age;

  /// The shared summary when their access is still open; null for someone
  /// whose share has closed (register, prescriptions and notes only).
  final Map<String, Object?>? share;
  final int sharedDaysAgo;
  final int shares;
}

/// A sample prescription, before it is signed on this device.
class SampleRx {
  const SampleRx(this.patient, this.medicine, this.ingredient, this.dose, this.days, this.daysAgo, {this.timing, this.note});
  final String patient;
  final String medicine;
  final String? ingredient;
  final List<int> dose;
  final int days;
  final int daysAgo;
  final String? timing;
  final String? note;
}

/// A sample private consult note.
class SampleNote {
  const SampleNote(this.patient, this.daysAgo, this.complaint, this.findings, this.advice, {this.followUpInDays});
  final String patient;
  final int daysAgo;
  final String complaint;
  final String findings;
  final String advice;
  final int? followUpInDays;
}

/// Stable LifeTrack IDs for the samples, so adding them again updates them.
String sampleId(String name) => LifeTrackId.generate(Random(name.hashCode ^ 0x5a17));

String _ago(DateTime now, int days) => now.subtract(Duration(days: days)).toIso8601String();

Map<String, Object?> _test(String id, String analyte, num value, String unit, int ageDays, String lab, {num? low, num? high, num? prev, String? prevOn, String source = 'photoOfReport'}) => {
      'recordId': id,
      'analyte': analyte,
      'value': value,
      'unit': unit,
      'ageDays': ageDays,
      'lab': lab,
      'printedRange': low == null && high == null ? null : {'low': low, 'high': high},
      if (prev != null) 'previous': {'value': prev, 'sampledOn': prevOn},
      'source': source,
    };

List<SamplePatient> samplePatients(DateTime now) => [
      SamplePatient('Meera Iyer (sample)', 'female', 54, shares: 3, share: {
        'levels': ['summary', 'homeReadings'],
        'allergies': [
          {'substance': 'Sulfa drugs', 'reaction': 'rash'},
        ],
        'conditions': [
          {'name': 'Type 2 diabetes', 'since': '2019'},
          {'name': 'High blood pressure', 'since': '2021'},
        ],
        'medicines': {
          'active': [
            {'title': 'Metformin 500 mg', 'dose': '1-0-1', 'patientConfirmedAt': _ago(now, 2), 'prescriber': 'Dr. S. Menon'},
            {'title': 'Glimepiride 1 mg', 'dose': '1-0-0', 'patientConfirmedAt': _ago(now, 2)},
            {'title': 'Telmisartan 40 mg', 'dose': '1-0-0'},
          ],
          'endedRecently': [
            {'title': 'Amoxicillin 500 mg', 'endsOn': _ago(now, 20)},
          ],
        },
        'latestTests': [
          _test('m1', 'hba1c', 7.8, '%', 21, 'Metropolis, Chennai', high: 5.6, prev: 8.4, prevOn: _ago(now, 110)),
          _test('m2', 'glucose_fasting', 142, 'mg/dL', 21, 'Metropolis, Chennai', low: 70, high: 100, prev: 156, prevOn: _ago(now, 110)),
          _test('m3', 'ldl', 118, 'mg/dL', 21, 'Metropolis, Chennai', high: 100),
          _test('m4', 'creatinine', 0.9, 'mg/dL', 95, 'Thyrocare', low: 0.6, high: 1.1, source: 'signed'),
        ],
        'homeReadings': {
          'items': [
            {'kind': 'glucose', 'glucose': 138, 'context': 'fasting', 'at': _ago(now, 1)},
            {'kind': 'bloodPressure', 'sys': 136, 'dia': 84, 'pulse': 76, 'at': _ago(now, 1)},
            {'kind': 'glucose', 'glucose': 182, 'context': 'afterMeal', 'at': _ago(now, 3)},
            {'kind': 'bloodPressure', 'sys': 142, 'dia': 88, 'pulse': 80, 'at': _ago(now, 6)},
          ],
        },
      }),
      SamplePatient('Rajesh Kumar (sample)', 'male', 61, shares: 2, share: {
        'levels': ['summary', 'familyIllnesses'],
        'allergies': [],
        'conditions': [
          {'name': 'Coronary artery disease', 'since': '2022'},
        ],
        'medicines': {
          'active': [
            {'title': 'Atorvastatin 20 mg', 'dose': '0-0-1', 'patientConfirmedAt': _ago(now, 5), 'prescriber': 'Dr. A. Bose'},
            {'title': 'Aspirin 75 mg', 'dose': '0-1-0', 'patientConfirmedAt': _ago(now, 5)},
            {'title': 'Metoprolol 25 mg', 'dose': '1-0-1'},
          ],
          'endedRecently': [],
        },
        'latestTests': [
          _test('r1', 'ldl', 96, 'mg/dL', 40, 'SRL Diagnostics', high: 100, prev: 142, prevOn: _ago(now, 220)),
          _test('r2', 'total_cholesterol', 168, 'mg/dL', 40, 'SRL Diagnostics', high: 200),
          _test('r3', 'triglycerides', 190, 'mg/dL', 40, 'SRL Diagnostics', high: 150),
          _test('r4', 'tsh', 2.1, 'mIU/L', 300, 'SRL Diagnostics', low: 0.4, high: 4.0, source: 'patientTyped'),
        ],
        'familyIllnesses': {
          'items': [
            {'relation': 'Father', 'condition': 'Heart attack', 'onset': '58'},
            {'relation': 'Mother', 'condition': 'Type 2 diabetes', 'onset': '50s'},
          ],
        },
      }),
      SamplePatient('Fatima Shaikh (sample)', 'female', 29, share: {
        'levels': ['allReports'],
        'withheld': ['Prescriptions'],
        'allergies': [],
        'conditions': [
          {'name': 'Iron-deficiency anaemia', 'since': '2025'},
        ],
        'medicines': {
          'active': [
            {'title': 'Ferrous ascorbate 100 mg', 'dose': '0-1-0', 'patientConfirmedAt': _ago(now, 1)},
            {'title': 'Cholecalciferol 60,000 IU', 'dose': 'weekly'},
          ],
          'endedRecently': [],
        },
        'latestTests': [
          _test('f1', 'haemoglobin', 10.2, 'g/dL', 12, 'Dr Lal PathLabs', low: 12, high: 15.5, prev: 9.1, prevOn: _ago(now, 75)),
          _test('f2', 'ferritin', 8, 'ng/mL', 12, 'Dr Lal PathLabs', low: 15, high: 150),
          _test('f3', 'vitamin_d', 14, 'ng/mL', 75, 'Dr Lal PathLabs', low: 30, high: 100),
        ],
        'documents': [
          {'id': 'fd1', 'title': 'Complete blood count', 'date': _ago(now, 12), 'kind': 'report', 'lab': 'Dr Lal PathLabs'},
          {'id': 'fd2', 'title': 'Iron studies', 'date': _ago(now, 12), 'kind': 'report', 'lab': 'Dr Lal PathLabs'},
          {'id': 'fd3', 'title': 'Vitamin D (25-OH)', 'date': _ago(now, 75), 'kind': 'report', 'lab': 'Dr Lal PathLabs'},
          {'id': 'fd4', 'title': 'Ultrasound abdomen', 'date': _ago(now, 140), 'kind': 'scan', 'lab': 'Aarthi Scans'},
        ],
      }),
      const SamplePatient('Arjun Mehta (sample)', 'male', 45, sharedDaysAgo: 9, shares: 2),
      const SamplePatient('Lakshmi Rao (sample)', 'female', 68, sharedDaysAgo: 23, shares: 4),
      const SamplePatient('Sunil Verma (sample)', 'male', 38, sharedDaysAgo: 41),
    ];

const sampleRx = [
  SampleRx('Arjun Mehta (sample)', 'Amlodipine 5 mg', 'amlodipine', [1, 0, 0], 30, 9, timing: 'after_food', note: 'Check BP at home twice a week.'),
  SampleRx('Arjun Mehta (sample)', 'Pantoprazole 40 mg', 'pantoprazole', [1, 0, 0], 14, 9, timing: 'before_food'),
  SampleRx('Lakshmi Rao (sample)', 'Levothyroxine 50 mcg', 'levothyroxine', [1, 0, 0], 90, 23, timing: 'before_food', note: 'Empty stomach, 30 minutes before tea.'),
  SampleRx('Lakshmi Rao (sample)', 'Calcium carbonate 500 mg + Vitamin D3', 'calcium carbonate', [0, 1, 0], 60, 23, timing: 'after_food'),
  SampleRx('Sunil Verma (sample)', 'Azithromycin 500 mg', 'azithromycin', [1, 0, 0], 3, 41, timing: 'after_food'),
  SampleRx('Meera Iyer (sample)', 'Metformin 500 mg', 'metformin', [1, 0, 1], 90, 60, timing: 'after_food'),
];

const sampleNotes = [
  SampleNote('Arjun Mehta (sample)', 9, 'Headaches in the morning for two weeks', 'BP 152/96 in clinic, repeated 148/94. No focal deficit.', 'Start amlodipine. Home BP log. Cut salt.', followUpInDays: 5),
  SampleNote('Lakshmi Rao (sample)', 23, 'Tiredness, weight gain', 'TSH 7.9 on outside report. Mild ankle swelling.', 'Levothyroxine 50 mcg. Repeat TSH in 6 weeks.', followUpInDays: 19),
  SampleNote('Sunil Verma (sample)', 41, 'Fever and cough, 4 days', 'Temp 38.4 °C, crackles right base.', 'Azithromycin 3 days. Chest X-ray if not better in 72 h.'),
  SampleNote('Meera Iyer (sample)', 60, 'Diabetes review', 'HbA1c 8.4. Feet normal. Fundus due.', 'Continue metformin; added glimepiride. Eye check.', followUpInDays: -2),
];
