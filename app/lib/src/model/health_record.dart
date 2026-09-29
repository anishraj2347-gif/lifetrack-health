/// A single document in the patient's record set.
enum RecordKind { prescription, report, scan, note }

/// Where a record came from. Kept on the record rather than discarded at the
/// write path: a result typed in by the patient and one issued by a lab carry
/// different weight, and export (FHIR `Provenance`) needs to say which.
enum RecordSource { typedByPatient, smartCapture, doctorIssued, restoredFromBackup }

/// The data classes a consent grant can be scoped to.
///
/// Personal notes and vitals are separate classes because they default to
/// local-only and are backed up only on opt-in (blueprint §5.2).
enum DataClass { prescriptions, reports, scans, personalNotes, vitals, emergencyCard }

DataClass dataClassOf(RecordKind kind) => switch (kind) {
      RecordKind.prescription => DataClass.prescriptions,
      RecordKind.report => DataClass.reports,
      RecordKind.scan => DataClass.scans,
      RecordKind.note => DataClass.personalNotes,
    };

/// One measured analyte on a report.
class LabResult {
  const LabResult({required this.analyte, required this.value, required this.unit});

  /// Canonical analyte key, e.g. `glucose_fasting`, `hba1c`. Matching is on
  /// this key only — free-text names are resolved to it at capture time.
  final String analyte;
  final double value;
  final String unit;

  Map<String, Object?> toJson() => {'analyte': analyte, 'value': value, 'unit': unit};

  static LabResult fromJson(Map<String, Object?> j) => LabResult(
        analyte: j['analyte']! as String,
        value: (j['value']! as num).toDouble(),
        unit: j['unit']! as String,
      );
}

/// Morning–afternoon–night dosing, as written on Indian prescriptions (1-0-1).
///
/// Structured rather than a display string, so a medication check can reason
/// about it; [display] reproduces the conventional notation.
class Dose {
  const Dose({required this.morning, required this.afternoon, required this.night});

  final int morning;
  final int afternoon;
  final int night;

  String get display => '$morning-$afternoon-$night';
  int get perDay => morning + afternoon + night;

  Map<String, Object?> toJson() => {'m': morning, 'a': afternoon, 'n': night};

  static Dose fromJson(Map<String, Object?> j) =>
      Dose(morning: j['m']! as int, afternoon: j['a']! as int, night: j['n']! as int);
}

class HealthRecord {
  const HealthRecord({
    required this.id,
    required this.patientId,
    required this.kind,
    required this.title,
    required this.date,
    required this.source,
    this.doctor,
    this.facility,
    this.results = const [],
    this.dose,
    this.ingredient,
  });

  final String id;
  final String patientId;
  final RecordKind kind;
  final String title;
  final DateTime date;
  final RecordSource source;
  final String? doctor;
  final String? facility;
  final List<LabResult> results;
  final Dose? dose;

  /// Active ingredient key for a prescription (e.g. `metformin`). Brand names
  /// differ; duplicate-medicine checks must compare ingredients.
  final String? ingredient;

  DataClass get dataClass => dataClassOf(kind);

  /// Doctor-issued documents are backed up automatically (blueprint §5.2).
  bool get backedUpByDefault => kind != RecordKind.note;

  Map<String, Object?> toJson() => {
        'id': id,
        'patientId': patientId,
        'kind': kind.name,
        'title': title,
        'date': date.toIso8601String(),
        'source': source.name,
        'doctor': doctor,
        'facility': facility,
        'results': [for (final r in results) r.toJson()],
        'dose': dose?.toJson(),
        'ingredient': ingredient,
      };

  static HealthRecord fromJson(Map<String, Object?> j) => HealthRecord(
        id: j['id']! as String,
        patientId: j['patientId']! as String,
        kind: RecordKind.values.byName(j['kind']! as String),
        title: j['title']! as String,
        date: DateTime.parse(j['date']! as String),
        source: RecordSource.values.byName((j['source'] as String?) ?? 'typedByPatient'),
        doctor: j['doctor'] as String?,
        facility: j['facility'] as String?,
        results: [
          for (final r in (j['results'] as List?) ?? const [])
            LabResult.fromJson((r as Map).cast<String, Object?>()),
        ],
        dose: j['dose'] == null ? null : Dose.fromJson((j['dose']! as Map).cast<String, Object?>()),
        ingredient: j['ingredient'] as String?,
      );
}
