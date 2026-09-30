/// A single document in the patient's record set.
enum RecordKind { prescription, report, scan, note }

/// Where a record came from. Kept on the record rather than discarded at the
/// write path: a result typed in by the patient and one issued by a lab carry
/// different weight, and export (FHIR `Provenance`) needs to say which.
enum RecordSource { typedByPatient, smartCapture, doctorIssued, restoredFromBackup, labSigned }

/// What a doctor can rely on, shown as a badge on every result. A doctor
/// reuses a result instead of re-ordering it only when they can trace it to
/// a lab (clinical review, 30 Sep 2026).
enum Provenance {
  /// Delivered by the lab or signed by a verified doctor.
  signed,

  /// Values typed or confirmed by the patient, with the original image kept.
  photoOfReport,

  /// Typed by the patient with no source attached.
  patientTyped,
}

/// The data classes a consent grant can be scoped to.
///
/// Personal notes and vitals are separate classes because they default to
/// local-only and are backed up only on opt-in (blueprint §5.2).
enum DataClass {
  prescriptions,
  reports,
  scans,
  personalNotes,
  vitals,
  emergencyCard,
  allergies,
  conditions,
  familyHistory,
}

DataClass dataClassOf(RecordKind kind) => switch (kind) {
      RecordKind.prescription => DataClass.prescriptions,
      RecordKind.report => DataClass.reports,
      RecordKind.scan => DataClass.scans,
      RecordKind.note => DataClass.personalNotes,
    };

/// One measured analyte on a report.
class LabResult {
  const LabResult({required this.analyte, required this.value, required this.unit, this.printedLow, this.printedHigh});

  /// Canonical analyte key, e.g. `glucose_fasting`, `hba1c`. Matching is on
  /// this key only — free-text names are resolved to it at capture time.
  final String analyte;
  final double value;
  final String unit;

  /// The reference range printed on this lab's report, in [unit]. Preferred
  /// over the generic table: labs differ by method and population.
  final double? printedLow;
  final double? printedHigh;

  bool get hasPrintedRange => printedLow != null || printedHigh != null;

  Map<String, Object?> toJson() => {
        'analyte': analyte,
        'value': value,
        'unit': unit,
        if (printedLow != null) 'lo': printedLow,
        if (printedHigh != null) 'hi': printedHigh,
      };

  static LabResult fromJson(Map<String, Object?> j) => LabResult(
        analyte: j['analyte']! as String,
        value: (j['value']! as num).toDouble(),
        unit: j['unit']! as String,
        printedLow: (j['lo'] as num?)?.toDouble(),
        printedHigh: (j['hi'] as num?)?.toDouble(),
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
    this.labName,
    this.sampleDate,
    this.attachmentId,
    this.endDate,
    this.patientConfirmedAt,
    this.instructions,
    this.timing,
    this.prescriberRegistration,
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

  /// Lab that ran a report, as printed on it. Never inferred.
  final String? labName;

  /// When the sample was collected — what decides whether a doctor can reuse
  /// a result. Falls back to [date] (the document date) when not captured.
  final DateTime? sampleDate;

  /// The original photo or PDF, kept so a doctor can check it.
  final String? attachmentId;

  /// For a prescription: when the course ends. Null = open-ended.
  final DateTime? endDate;

  /// When the patient last confirmed they are still taking this medicine.
  final DateTime? patientConfirmedAt;

  /// The prescriber's own words to the patient ("Repeat lipid panel in 3
  /// months"). Reproduced exactly; never rewritten by the app.
  final String? instructions;

  /// `before_food`, `after_food`, `with_food`, or null.
  final String? timing;

  /// The prescriber's registration number, from a verified signature.
  final String? prescriberRegistration;

  DataClass get dataClass => dataClassOf(kind);

  /// Every field carried over; only [source] and [patientConfirmedAt] ever
  /// change after a record is written.
  HealthRecord copyWith({RecordSource? source, DateTime? patientConfirmedAt}) => HealthRecord(
        id: id,
        patientId: patientId,
        kind: kind,
        title: title,
        date: date,
        source: source ?? this.source,
        doctor: doctor,
        facility: facility,
        results: results,
        dose: dose,
        ingredient: ingredient,
        labName: labName,
        sampleDate: sampleDate,
        attachmentId: attachmentId,
        endDate: endDate,
        patientConfirmedAt: patientConfirmedAt ?? this.patientConfirmedAt,
        instructions: instructions,
        timing: timing,
        prescriberRegistration: prescriberRegistration,
      );

  DateTime get effectiveDate => sampleDate ?? date;

  /// `doctorIssued` is only ever written by the verified inbound-prescription
  /// path (signature checked against a registry-certified doctor key), so it
  /// counts as signed. Everything the patient enters is not.
  Provenance get provenance {
    if (source == RecordSource.labSigned || source == RecordSource.doctorIssued) return Provenance.signed;
    if (attachmentId != null) return Provenance.photoOfReport;
    return Provenance.patientTyped;
  }

  /// A prescription is active until its end date. Whether the patient still
  /// takes it is a separate fact ([patientConfirmedAt]), shown beside it.
  bool isActiveAt(DateTime at) => kind == RecordKind.prescription && (endDate == null || at.isBefore(endDate!));

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
        if (labName != null) 'lab': labName,
        if (sampleDate != null) 'sampled': sampleDate!.toIso8601String(),
        if (attachmentId != null) 'attachment': attachmentId,
        if (endDate != null) 'ends': endDate!.toIso8601String(),
        if (patientConfirmedAt != null) 'confirmed': patientConfirmedAt!.toIso8601String(),
        if (instructions != null) 'instructions': instructions,
        if (timing != null) 'timing': timing,
        if (prescriberRegistration != null) 'prescriberReg': prescriberRegistration,
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
        labName: j['lab'] as String?,
        sampleDate: _date(j['sampled']),
        attachmentId: j['attachment'] as String?,
        endDate: _date(j['ends']),
        patientConfirmedAt: _date(j['confirmed']),
        instructions: j['instructions'] as String?,
        timing: j['timing'] as String?,
        prescriberRegistration: j['prescriberReg'] as String?,
      );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
}
