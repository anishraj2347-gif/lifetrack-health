import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';

/// Sample records for "Explore with sample records". Only ever written when
/// the patient chooses it at onboarding, into an empty store — never on a
/// later launch, where it would overwrite the patient's own records.
///
/// No sample audit entries: a log that looks populated when it is not is a
/// false statement about who has seen the records.
abstract final class DemoData {
  static Patient patient(String id) => Patient(
        id: id,
        name: 'Anjali Sharma',
        dateOfBirth: DateTime(1984, 6, 14),
        sex: Sex.female,
      );

  static ClinicalProfile profile(DateTime at) => ClinicalProfile(
        allergies: const [Allergy(substance: 'Penicillin', reaction: 'rash')],
        conditions: const [Condition(name: 'Type 2 diabetes', sinceYear: 2021), Condition(name: 'Hypertension', sinceYear: 2023)],
        familyIllnesses: const [
          FamilyIllness(relation: Relation.father, condition: 'Heart attack', ageAtOnset: 58),
          FamilyIllness(relation: Relation.mother, condition: 'Type 2 diabetes', ageAtOnset: 45),
        ],
        updatedAt: at,
      );

  static List<HealthRecord> records(String patientId) {
    HealthRecord report(String id, String title, DateTime date, String doctor, String lab, List<LabResult> results, {bool photo = true}) =>
        HealthRecord(
          id: id,
          patientId: patientId,
          kind: RecordKind.report,
          title: title,
          date: date,
          sampleDate: date,
          source: photo ? RecordSource.smartCapture : RecordSource.typedByPatient,
          attachmentId: photo ? 'demo-photo-$id' : null,
          labName: lab,
          doctor: doctor,
          facility: lab,
          results: results,
        );

    return [
      report('demo-hba1c-2026-09', 'HbA1c', DateTime(2026, 9, 8), 'Dr. S. Iyer', 'Thyrocare', const [
        LabResult(analyte: 'hba1c', value: 6.1, unit: '%', printedHigh: 5.6),
      ]),
      report('demo-lipid-2026-03', 'Lipid panel', DateTime(2026, 3, 9), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
        LabResult(analyte: 'total_cholesterol', value: 214, unit: 'mg/dL', printedHigh: 200),
        LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL', printedHigh: 100),
        LabResult(analyte: 'hdl', value: 52, unit: 'mg/dL', printedLow: 50),
        LabResult(analyte: 'triglycerides', value: 141, unit: 'mg/dL', printedHigh: 150),
      ]),
      report('demo-glucose-2026-03', 'Fasting glucose', DateTime(2026, 3, 9), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
        LabResult(analyte: 'glucose_fasting', value: 112, unit: 'mg/dL', printedLow: 70, printedHigh: 100),
      ]),
      report('demo-creatinine-2025-10', 'Creatinine', DateTime(2025, 10, 20), 'Dr. S. Iyer', 'Unknown lab', const [
        LabResult(analyte: 'creatinine', value: 0.9, unit: 'mg/dL'),
      ], photo: false),
      HealthRecord(
        id: 'demo-rx-metformin-2026-03',
        patientId: patientId,
        kind: RecordKind.prescription,
        title: 'Metformin 500 mg',
        date: DateTime(2026, 3, 2),
        source: RecordSource.smartCapture,
        attachmentId: 'demo-photo-rx-metformin',
        doctor: 'Dr. S. Iyer',
        facility: 'Fortis',
        dose: const Dose(morning: 1, afternoon: 0, night: 1),
        ingredient: 'metformin',
      ),
      HealthRecord(
        id: 'demo-rx-glycomet-2026-02',
        patientId: patientId,
        kind: RecordKind.prescription,
        title: 'Glycomet 500 SR',
        date: DateTime(2026, 2, 11),
        source: RecordSource.smartCapture,
        attachmentId: 'demo-photo-rx-glycomet',
        doctor: 'Dr. R. Mehta',
        facility: 'Apollo',
        dose: const Dose(morning: 0, afternoon: 0, night: 1),
        ingredient: 'metformin',
        endDate: DateTime(2026, 3, 1),
      ),
      HealthRecord(
        id: 'demo-xray-2026-01',
        patientId: patientId,
        kind: RecordKind.scan,
        title: 'Chest X-ray',
        date: DateTime(2026, 1, 18),
        source: RecordSource.smartCapture,
        attachmentId: 'demo-photo-xray',
        doctor: 'Dr. R. Mehta',
        facility: 'Apollo',
      ),
      report('demo-hba1c-2026-01', 'HbA1c', DateTime(2026, 1, 5), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'hba1c', value: 6.4, unit: '%'),
      ]),
      report('demo-cbc-2025-11', 'Complete blood count', DateTime(2025, 11, 20), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'haemoglobin', value: 11.4, unit: 'g/dL'),
        LabResult(analyte: 'vitamin_d', value: 18, unit: 'ng/mL'),
      ]),
      report('demo-hba1c-2025-07', 'HbA1c', DateTime(2025, 7, 2), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'hba1c', value: 6.8, unit: '%'),
      ]),
      // More history, so some tests have three results (a trend) and some two.
      report('demo-lipid-2025-09', 'Lipid panel', DateTime(2025, 9, 15), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
        LabResult(analyte: 'total_cholesterol', value: 228, unit: 'mg/dL', printedHigh: 200),
        LabResult(analyte: 'ldl', value: 148, unit: 'mg/dL', printedHigh: 100),
        LabResult(analyte: 'hdl', value: 48, unit: 'mg/dL', printedLow: 50),
        LabResult(analyte: 'triglycerides', value: 162, unit: 'mg/dL', printedHigh: 150),
      ]),
      report('demo-lipid-2026-09', 'Lipid panel', DateTime(2026, 9, 22), 'Dr. R. Mehta', 'Apollo Diagnostics', const [
        LabResult(analyte: 'total_cholesterol', value: 198, unit: 'mg/dL', printedHigh: 200),
        LabResult(analyte: 'ldl', value: 118, unit: 'mg/dL', printedHigh: 100),
        LabResult(analyte: 'hdl', value: 55, unit: 'mg/dL', printedLow: 50),
        LabResult(analyte: 'triglycerides', value: 128, unit: 'mg/dL', printedHigh: 150),
      ]),
      report('demo-glucose-2025-07', 'Fasting glucose', DateTime(2025, 7, 2), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'glucose_fasting', value: 118, unit: 'mg/dL', printedLow: 70, printedHigh: 100),
      ]),
      report('demo-glucose-2026-09', 'Fasting glucose', DateTime(2026, 9, 8), 'Dr. S. Iyer', 'Thyrocare', const [
        LabResult(analyte: 'glucose_fasting', value: 104, unit: 'mg/dL', printedLow: 70, printedHigh: 100),
      ]),
      report('demo-thyroid-2025-12', 'Thyroid (TSH)', DateTime(2025, 12, 12), 'Dr. S. Iyer', 'Thyrocare', const [
        LabResult(analyte: 'tsh', value: 3.1, unit: 'mIU/L', printedLow: 0.4, printedHigh: 4.0),
      ]),
      report('demo-cbc-2026-06', 'Complete blood count', DateTime(2026, 6, 14), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'haemoglobin', value: 12.1, unit: 'g/dL', printedLow: 12, printedHigh: 15),
        LabResult(analyte: 'vitamin_d', value: 31, unit: 'ng/mL'),
        LabResult(analyte: 'tsh', value: 2.6, unit: 'mIU/L', printedLow: 0.4, printedHigh: 4.0),
      ]),
      report('demo-creatinine-2026-09', 'Creatinine', DateTime(2026, 9, 8), 'Dr. S. Iyer', 'Thyrocare', const [
        LabResult(analyte: 'creatinine', value: 0.8, unit: 'mg/dL'),
      ], photo: false),
    ];
  }
}
