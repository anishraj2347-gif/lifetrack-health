import '../emergency/emergency_card.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';
import '../model/vital_reading.dart';

/// One sample relative for demonstrations: who they are to the head of
/// family (Anjali Sharma in [DemoData]), and a small, believable record.
/// Every name here is made up; the faces are cropped from the app's own
/// AI-generated photos, and Savitri's and Prakash's were generated in Canva
/// on 12 Oct 2026 (assets/photos/people/).
class DemoRelative {
  const DemoRelative({
    required this.key,
    required this.name,
    required this.dob,
    required this.sex,
    required this.role,
    this.photo,
    this.profile = const ClinicalProfile(),
    this.emergency,
    this.vaccinesUpTo,
    this.records = _none,
    this.vitals = _noVitals,
  });

  final String key;
  final String name;
  final DateTime dob;
  final Sex sex;

  /// A [FamilyRole] name, relative to the head of family.
  final String role;

  /// Asset path of the face, if one fits this person.
  final String? photo;
  final ClinicalProfile profile;
  final EmergencyCard? emergency;

  /// Children: every UIP dose up to and including this code is marked given.
  final String? vaccinesUpTo;
  final List<HealthRecord> Function(String patientId) records;
  final List<VitalReading> Function(String patientId) vitals;

  bool get isChild => role == 'son' || role == 'daughter';

  static List<HealthRecord> _none(String _) => const [];
  static List<VitalReading> _noVitals(String _) => const [];
}

/// The nine relatives that, with the head, make a ten-person family across
/// four generations — grandmother; the head's parents and her husband's
/// parents; the head, her husband and her brother; their two children.
abstract final class DemoFamily {
  static const headPhoto = 'assets/photos/people/anjali.jpg';

  static HealthRecord _report(String pid, String id, String title, DateTime date, String doctor, String lab, List<LabResult> results) => HealthRecord(
        id: '$pid-$id',
        patientId: pid,
        kind: RecordKind.report,
        title: title,
        date: date,
        sampleDate: date,
        source: RecordSource.smartCapture,
        attachmentId: 'demo-photo-$pid-$id',
        labName: lab,
        doctor: doctor,
        facility: lab,
        results: results,
      );

  static HealthRecord _rx(String pid, String id, String title, DateTime date, String doctor, String facility, Dose? dose, String ingredient, {DateTime? ends, String? instructions}) =>
      HealthRecord(
        id: '$pid-$id',
        patientId: pid,
        kind: RecordKind.prescription,
        title: title,
        date: date,
        source: RecordSource.typedByPatient,
        doctor: doctor,
        facility: facility,
        dose: dose,
        ingredient: ingredient,
        endDate: ends,
        instructions: instructions,
      );

  static List<VitalReading> _bp(String pid, List<(DateTime, int, int, int)> rows) => [
        for (final (i, (at, s, d, p)) in rows.indexed)
          VitalReading(id: '$pid-bp-$i', patientId: pid, at: at, kind: VitalKind.bloodPressure, systolic: s, diastolic: d, pulse: p),
      ];

  static List<VitalReading> _sugar(String pid, List<(DateTime, int)> rows) => [
        for (final (i, (at, g)) in rows.indexed)
          VitalReading(id: '$pid-sugar-$i', patientId: pid, at: at, kind: VitalKind.glucose, glucose: g.toDouble(), context: GlucoseContext.fasting),
      ];

  static final members = <DemoRelative>[
    DemoRelative(
      key: 'savitri',
      name: 'Savitri Gupta',
      dob: DateTime(1936, 3, 2),
      sex: Sex.female,
      role: 'grandmother',
      photo: 'assets/photos/people/savitri.jpg',
      profile: const ClinicalProfile(conditions: [Condition(name: 'Hypertension', sinceYear: 2005), Condition(name: 'Osteoarthritis (knees)', sinceYear: 2010)]),
      emergency: const EmergencyCard(bloodType: 'O+', conditions: 'Hypertension', medications: 'Amlodipine 5 mg', contactName: 'Anjali Sharma', contactRelation: 'Granddaughter', contactPhone: '+91 98100 00000'),
      records: (p) => [
        _report(p, 'cbc-2026-08', 'Complete blood count', DateTime(2026, 8, 18), 'Dr. N. Rao', 'Metropolis', const [LabResult(analyte: 'haemoglobin', value: 10.9, unit: 'g/dL', printedLow: 12, printedHigh: 15)]),
        _report(p, 'kft-2026-08', 'Kidney function', DateTime(2026, 8, 18), 'Dr. N. Rao', 'Metropolis', const [LabResult(analyte: 'creatinine', value: 1.3, unit: 'mg/dL', printedLow: 0.6, printedHigh: 1.1)]),
        _rx(p, 'rx-amlodipine', 'Amlodipine 5 mg', DateTime(2026, 4, 2), 'Dr. N. Rao', 'Max Clinic', const Dose(morning: 1, afternoon: 0, night: 0), 'amlodipine'),
        _rx(p, 'rx-calcium', 'Calcium + Vitamin D3', DateTime(2026, 4, 2), 'Dr. N. Rao', 'Max Clinic', const Dose(morning: 0, afternoon: 0, night: 1), 'calcium carbonate'),
      ],
      vitals: (p) => _bp(p, [(DateTime(2026, 10, 6, 8), 148, 86, 74), (DateTime(2026, 10, 9, 8), 142, 84, 72), (DateTime(2026, 10, 11, 8), 138, 82, 70)]),
    ),
    DemoRelative(
      key: 'prakash',
      name: 'Prakash Gupta',
      dob: DateTime(1952, 11, 20),
      sex: Sex.male,
      role: 'father',
      photo: 'assets/photos/people/prakash.jpg',
      profile: const ClinicalProfile(
        allergies: [Allergy(substance: 'Sulfa drugs', reaction: 'hives')],
        conditions: [Condition(name: 'Type 2 diabetes', sinceYear: 2008), Condition(name: 'Coronary artery disease', sinceYear: 2018)],
      ),
      emergency: const EmergencyCard(bloodType: 'B+', allergies: 'Sulfa drugs', conditions: 'Type 2 diabetes; heart disease (stent 2018)', medications: 'Metformin, Atorvastatin, Aspirin', contactName: 'Anjali Sharma', contactRelation: 'Daughter', contactPhone: '+91 98100 00000'),
      records: (p) => [
        _report(p, 'hba1c-2026-09', 'HbA1c', DateTime(2026, 9, 12), 'Dr. S. Iyer', 'Thyrocare', const [LabResult(analyte: 'hba1c', value: 7.4, unit: '%', printedHigh: 5.6)]),
        _report(p, 'hba1c-2026-03', 'HbA1c', DateTime(2026, 3, 10), 'Dr. S. Iyer', 'Thyrocare', const [LabResult(analyte: 'hba1c', value: 7.9, unit: '%', printedHigh: 5.6)]),
        _report(p, 'lipid-2026-09', 'Lipid panel', DateTime(2026, 9, 12), 'Dr. S. Iyer', 'Thyrocare', const [
          LabResult(analyte: 'total_cholesterol', value: 162, unit: 'mg/dL', printedHigh: 200),
          LabResult(analyte: 'ldl', value: 84, unit: 'mg/dL', printedHigh: 100),
          LabResult(analyte: 'hdl', value: 41, unit: 'mg/dL', printedLow: 40),
          LabResult(analyte: 'triglycerides', value: 171, unit: 'mg/dL', printedHigh: 150),
        ]),
        _rx(p, 'rx-metformin', 'Metformin 500 mg', DateTime(2026, 3, 12), 'Dr. S. Iyer', 'Fortis', const Dose(morning: 1, afternoon: 0, night: 1), 'metformin'),
        _rx(p, 'rx-atorva', 'Atorvastatin 20 mg', DateTime(2026, 3, 12), 'Dr. A. Kapoor', 'Fortis Heart', const Dose(morning: 0, afternoon: 0, night: 1), 'atorvastatin'),
        _rx(p, 'rx-aspirin', 'Aspirin 75 mg', DateTime(2026, 3, 12), 'Dr. A. Kapoor', 'Fortis Heart', const Dose(morning: 0, afternoon: 1, night: 0), 'aspirin', instructions: 'After lunch'),
      ],
      vitals: (p) => _sugar(p, [(DateTime(2026, 10, 5, 7), 148), (DateTime(2026, 10, 8, 7), 139), (DateTime(2026, 10, 11, 7), 131)]),
    ),
    DemoRelative(
      key: 'kamla',
      name: 'Kamla Gupta',
      dob: DateTime(1956, 7, 8),
      sex: Sex.female,
      role: 'mother',
      photo: 'assets/photos/people/kamla.jpg',
      profile: const ClinicalProfile(conditions: [Condition(name: 'Hypothyroidism', sinceYear: 2015)]),
      records: (p) => [
        _report(p, 'tsh-2026-08', 'Thyroid (TSH)', DateTime(2026, 8, 25), 'Dr. P. Menon', 'SRL', const [LabResult(analyte: 'tsh', value: 5.8, unit: 'mIU/L', printedLow: 0.4, printedHigh: 4.0)]),
        _report(p, 'tsh-2026-02', 'Thyroid (TSH)', DateTime(2026, 2, 20), 'Dr. P. Menon', 'SRL', const [LabResult(analyte: 'tsh', value: 4.6, unit: 'mIU/L', printedLow: 0.4, printedHigh: 4.0)]),
        _report(p, 'vitd-2026-08', 'Vitamin D', DateTime(2026, 8, 25), 'Dr. P. Menon', 'SRL', const [LabResult(analyte: 'vitamin_d', value: 14, unit: 'ng/mL')]),
        _rx(p, 'rx-thyronorm', 'Thyronorm 50 mcg', DateTime(2026, 8, 28), 'Dr. P. Menon', 'Apollo', const Dose(morning: 1, afternoon: 0, night: 0), 'levothyroxine', instructions: 'Empty stomach, 30 minutes before breakfast'),
      ],
    ),
    DemoRelative(
      key: 'ramesh',
      name: 'Ramesh Sharma',
      dob: DateTime(1955, 1, 10),
      sex: Sex.male,
      role: 'fatherInLaw',
      photo: 'assets/photos/people/ramesh.jpg',
      profile: const ClinicalProfile(conditions: [Condition(name: 'Hypertension', sinceYear: 2012)]),
      records: (p) => [
        _report(p, 'lipid-2026-07', 'Lipid panel', DateTime(2026, 7, 14), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
          LabResult(analyte: 'total_cholesterol', value: 221, unit: 'mg/dL', printedHigh: 200),
          LabResult(analyte: 'ldl', value: 141, unit: 'mg/dL', printedHigh: 100),
          LabResult(analyte: 'hdl', value: 44, unit: 'mg/dL', printedLow: 40),
          LabResult(analyte: 'triglycerides', value: 152, unit: 'mg/dL', printedHigh: 150),
        ]),
        _report(p, 'kft-2026-07', 'Kidney function', DateTime(2026, 7, 14), 'Dr. R. Mehta', 'Apollo Diagnostics', const [LabResult(analyte: 'creatinine', value: 1.1, unit: 'mg/dL', printedLow: 0.7, printedHigh: 1.3)]),
        _rx(p, 'rx-telmisartan', 'Telmisartan 40 mg', DateTime(2026, 1, 20), 'Dr. R. Mehta', 'Apollo', const Dose(morning: 1, afternoon: 0, night: 0), 'telmisartan'),
      ],
      vitals: (p) => _bp(p, [(DateTime(2026, 10, 4, 9), 152, 92, 78), (DateTime(2026, 10, 8, 9), 146, 90, 76), (DateTime(2026, 10, 11, 9), 140, 88, 74)]),
    ),
    DemoRelative(
      key: 'sunita',
      name: 'Sunita Sharma',
      dob: DateTime(1958, 5, 25),
      sex: Sex.female,
      role: 'motherInLaw',
      photo: 'assets/photos/people/sunita.jpg',
      profile: const ClinicalProfile(conditions: [Condition(name: 'Type 2 diabetes', sinceYear: 2019)]),
      records: (p) => [
        _report(p, 'fbs-2026-09', 'Fasting glucose', DateTime(2026, 9, 3), 'Dr. R. Mehta', 'Apollo Diagnostics', const [LabResult(analyte: 'glucose_fasting', value: 132, unit: 'mg/dL', printedLow: 70, printedHigh: 100)]),
        _report(p, 'hba1c-2026-09', 'HbA1c', DateTime(2026, 9, 3), 'Dr. R. Mehta', 'Apollo Diagnostics', const [LabResult(analyte: 'hba1c', value: 6.9, unit: '%', printedHigh: 5.6)]),
        _report(p, 'hba1c-2026-04', 'HbA1c', DateTime(2026, 4, 1), 'Dr. R. Mehta', 'Apollo Diagnostics', const [LabResult(analyte: 'hba1c', value: 7.2, unit: '%', printedHigh: 5.6)]),
        _rx(p, 'rx-glimepiride', 'Glimepiride 1 mg', DateTime(2026, 4, 3), 'Dr. R. Mehta', 'Apollo', const Dose(morning: 1, afternoon: 0, night: 0), 'glimepiride', instructions: 'Before breakfast'),
      ],
      vitals: (p) => _sugar(p, [(DateTime(2026, 10, 7, 7), 128), (DateTime(2026, 10, 10, 7), 121)]),
    ),
    DemoRelative(
      key: 'vikram',
      name: 'Vikram Sharma',
      dob: DateTime(1982, 3, 2),
      sex: Sex.male,
      role: 'husband',
      photo: 'assets/photos/people/vikram.jpg',
      profile: const ClinicalProfile(familyIllnesses: [FamilyIllness(relation: Relation.father, condition: 'Hypertension', ageAtOnset: 57)]),
      records: (p) => [
        _report(p, 'lipid-2026-07', 'Lipid panel', DateTime(2026, 7, 20), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
          LabResult(analyte: 'total_cholesterol', value: 204, unit: 'mg/dL', printedHigh: 200),
          LabResult(analyte: 'ldl', value: 128, unit: 'mg/dL', printedHigh: 100),
          LabResult(analyte: 'hdl', value: 46, unit: 'mg/dL', printedLow: 40),
          LabResult(analyte: 'triglycerides', value: 139, unit: 'mg/dL', printedHigh: 150),
        ]),
        _report(p, 'vitd-2026-07', 'Vitamin D', DateTime(2026, 7, 20), 'Dr. R. Mehta', 'Apollo Diagnostics', const [LabResult(analyte: 'vitamin_d', value: 22, unit: 'ng/mL')]),
      ],
    ),
    DemoRelative(
      key: 'rohit',
      name: 'Rohit Gupta',
      dob: DateTime(1979, 12, 15),
      sex: Sex.male,
      role: 'brother',
      photo: 'assets/photos/people/rohit.jpg',
      profile: const ClinicalProfile(conditions: [Condition(name: 'Fatty liver (grade 1)', sinceYear: 2024)]),
      records: (p) => [
        _report(p, 'hba1c-2026-06', 'HbA1c', DateTime(2026, 6, 9), 'Dr. K. Bhat', 'Lal PathLabs', const [LabResult(analyte: 'hba1c', value: 5.9, unit: '%', printedHigh: 5.6)]),
        _report(p, 'lipid-2026-06', 'Lipid panel', DateTime(2026, 6, 9), 'Dr. K. Bhat', 'Lal PathLabs', const [
          LabResult(analyte: 'total_cholesterol', value: 236, unit: 'mg/dL', printedHigh: 200),
          LabResult(analyte: 'ldl', value: 152, unit: 'mg/dL', printedHigh: 100),
          LabResult(analyte: 'hdl', value: 38, unit: 'mg/dL', printedLow: 40),
          LabResult(analyte: 'triglycerides', value: 214, unit: 'mg/dL', printedHigh: 150),
        ]),
        HealthRecord(id: '$p-us-2026-06', patientId: p, kind: RecordKind.scan, title: 'Ultrasound abdomen', date: DateTime(2026, 6, 11), source: RecordSource.typedByPatient, doctor: 'Dr. K. Bhat', facility: 'Lal PathLabs'),
      ],
    ),
    DemoRelative(
      key: 'aarav',
      name: 'Aarav Sharma',
      dob: DateTime(2014, 4, 11),
      sex: Sex.male,
      role: 'son',
      photo: 'assets/photos/people/aarav.jpg',
      vaccinesUpTo: 'dpt-b2',
      profile: const ClinicalProfile(allergies: [Allergy(substance: 'Peanuts', reaction: 'swelling of lips')], conditions: [Condition(name: 'Asthma (mild)', sinceYear: 2019)]),
      emergency: const EmergencyCard(bloodType: 'B+', allergies: 'Peanuts', conditions: 'Asthma', medications: 'Salbutamol inhaler when needed', contactName: 'Anjali Sharma', contactRelation: 'Mother', contactPhone: '+91 98100 00000'),
      records: (p) => [
        _rx(p, 'rx-salbutamol', 'Salbutamol inhaler 100 mcg', DateTime(2026, 2, 14), 'Dr. M. Das', 'Rainbow Children\'s Hospital', null, 'salbutamol', instructions: '2 puffs when wheezing'),
        _report(p, 'cbc-2026-05', 'Complete blood count', DateTime(2026, 5, 6), 'Dr. M. Das', 'Rainbow Children\'s Hospital', const [LabResult(analyte: 'haemoglobin', value: 12.6, unit: 'g/dL', printedLow: 11.5, printedHigh: 15.5)]),
      ],
    ),
    DemoRelative(
      key: 'myra',
      name: 'Myra Sharma',
      dob: DateTime(2019, 8, 5),
      sex: Sex.female,
      role: 'daughter',
      photo: 'assets/photos/people/myra.jpg',
      vaccinesUpTo: 'opv-b',
      records: (p) => [
        _rx(p, 'rx-amoxicillin', 'Amoxicillin 250 mg syrup', DateTime(2026, 7, 2), 'Dr. M. Das', 'Rainbow Children\'s Hospital', const Dose(morning: 1, afternoon: 1, night: 1), 'amoxicillin',
            ends: DateTime(2026, 7, 8), instructions: '5 ml each time, for 7 days'),
      ],
    ),
  ];
}
