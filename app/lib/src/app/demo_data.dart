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

  static List<HealthRecord> records(String patientId) {
    HealthRecord report(String id, String title, DateTime date, String doctor, String facility, List<LabResult> results) =>
        HealthRecord(
          id: id,
          patientId: patientId,
          kind: RecordKind.report,
          title: title,
          date: date,
          source: RecordSource.doctorIssued,
          doctor: doctor,
          facility: facility,
          results: results,
        );

    return [
      report('demo-lipid-2026-03', 'Lipid panel', DateTime(2026, 3, 9), 'Dr. R. Mehta', 'Apollo', const [
        LabResult(analyte: 'total_cholesterol', value: 214, unit: 'mg/dL'),
        LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL'),
        LabResult(analyte: 'hdl', value: 52, unit: 'mg/dL'),
        LabResult(analyte: 'triglycerides', value: 141, unit: 'mg/dL'),
      ]),
      report('demo-glucose-2026-03', 'Fasting glucose', DateTime(2026, 3, 9), 'Dr. R. Mehta', 'Apollo', const [
        LabResult(analyte: 'glucose_fasting', value: 112, unit: 'mg/dL'),
      ]),
      HealthRecord(
        id: 'demo-rx-metformin-2026-03',
        patientId: patientId,
        kind: RecordKind.prescription,
        title: 'Metformin 500 mg',
        date: DateTime(2026, 3, 2),
        source: RecordSource.doctorIssued,
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
        source: RecordSource.doctorIssued,
        doctor: 'Dr. R. Mehta',
        facility: 'Apollo',
        dose: const Dose(morning: 0, afternoon: 0, night: 1),
        ingredient: 'metformin',
      ),
      HealthRecord(
        id: 'demo-xray-2026-01',
        patientId: patientId,
        kind: RecordKind.scan,
        title: 'Chest X-ray',
        date: DateTime(2026, 1, 18),
        source: RecordSource.doctorIssued,
        doctor: 'Dr. R. Mehta',
        facility: 'Apollo',
      ),
      report('demo-hba1c-2026-01', 'HbA1c', DateTime(2026, 1, 5), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'hba1c', value: 6.1, unit: '%'),
      ]),
      report('demo-cbc-2025-11', 'Complete blood count', DateTime(2025, 11, 20), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'haemoglobin', value: 11.4, unit: 'g/dL'),
        LabResult(analyte: 'vitamin_d', value: 18, unit: 'ng/mL'),
      ]),
      report('demo-hba1c-2025-07', 'HbA1c', DateTime(2025, 7, 2), 'Dr. S. Iyer', 'Fortis', const [
        LabResult(analyte: 'hba1c', value: 6.8, unit: '%'),
      ]),
    ];
  }
}
