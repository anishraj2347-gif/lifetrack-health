import '../consent/consent_token.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';

/// Builds what a doctor receives, on the patient's phone, from data already
/// released through `RecordAccess` (so every part of it was authorized and
/// audited).
///
/// Shaped for a 60-second read in an OPD (clinical review): allergies first,
/// then active medicines, conditions, the latest result of each test with its
/// source and age, then family illnesses. It states what was withheld — but
/// never what the withheld items contain.
///
/// It carries facts and their age, never a judgement: no "valid", "expired",
/// "normal" or "abnormal" (CLAUDE.md #16).
abstract final class ShareBundle {
  static const schema = 'lifetrack.share/1';

  static Map<String, Object?> build({
    required Patient patient,
    required DateTime at,
    required Set<AccessLevel> levels,
    required RecordFilter? filter,
    required Set<DataClass> requested,
    required Set<DataClass> granted,
    required List<Allergy> allergies,
    required List<Condition> conditions,
    required List<FamilyIllness> familyIllnesses,
    required List<HealthRecord> prescriptions,
    required List<HealthRecord> reports,
    required List<HealthRecord> scans,
    DateTime? profileUpdatedAt,
  }) {
    final f = filter ?? const RecordFilter();
    bool admit(HealthRecord r) => f.admitsDate(r.effectiveDate);

    final activeMeds = [for (final r in prescriptions) if (r.isActiveAt(at)) r];
    final recentlyEnded = [
      for (final r in prescriptions)
        if (!r.isActiveAt(at) && r.endDate != null && at.difference(r.endDate!).inDays <= 365) r,
    ];

    return {
      'schema': schema,
      'sharedAt': at.toUtc().toIso8601String(),
      'levels': [for (final l in levels) l.name],
      'filter': f.isEmpty ? null : f.toJson(),
      'withheld': [for (final c in requested.difference(granted)) c.name],
      // The phone's random profile id, so a prescription can be addressed
      // back to this profile. Not a name, phone number or ABHA id.
      'patientRef': patient.id,
      'patient': {
        'name': patient.name,
        'age': patient.ageAt(at),
        'sex': patient.sex.name,
        if (patient.pregnant) 'pregnant': true,
      },
      'profileUpdatedAt': profileUpdatedAt?.toUtc().toIso8601String(),
      'allergies': [for (final a in allergies) a.toJson()],
      'conditions': [for (final c in conditions) c.toJson()],
      'medicines': {
        'active': [for (final r in activeMeds) _medicine(r, at)],
        'endedRecently': [for (final r in recentlyEnded) _medicine(r, at)],
      },
      if (levels.contains(AccessLevel.summary) || levels.contains(AccessLevel.allReports))
        'latestTests': _latestTests([for (final r in reports) if (admit(r)) r], f, at),
      if (levels.contains(AccessLevel.allReports))
        'documents': [
          for (final r in [...reports, ...prescriptions, ...scans]..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate)))
            if (admit(r)) _document(r, at),
        ],
      if (levels.contains(AccessLevel.familyIllnesses))
        'familyIllnesses': {
          'reportedBy': 'patient',
          'items': [for (final i in familyIllnesses) i.toJson()],
        },
    };
  }

  static Map<String, Object?> _medicine(HealthRecord r, DateTime at) => {
        'title': r.title,
        'ingredient': r.ingredient,
        'dose': r.dose?.display,
        'prescribedOn': r.date.toIso8601String(),
        'prescriber': r.doctor,
        'endsOn': r.endDate?.toIso8601String(),
        'patientConfirmedAt': r.patientConfirmedAt?.toIso8601String(),
        'timing': r.timing,
        'instructions': r.instructions,
        'source': r.provenance.name,
      };

  /// Latest result per test, with the previous one for context.
  static List<Map<String, Object?>> _latestTests(List<HealthRecord> reports, RecordFilter f, DateTime at) {
    final series = <String, List<(HealthRecord, LabResult)>>{};
    for (final r in reports) {
      for (final res in r.results) {
        if (f.analytes != null && f.analytes!.isNotEmpty && !f.analytes!.contains(res.analyte)) continue;
        series.putIfAbsent(res.analyte, () => []).add((r, res));
      }
    }
    return [
      for (final MapEntry(key: analyte, value: pts) in series.entries)
        () {
          pts.sort((a, b) => b.$1.effectiveDate.compareTo(a.$1.effectiveDate));
          final (rec, res) = pts.first;
          final prev = pts.length > 1 ? pts[1] : null;
          return {
            'analyte': analyte,
            'value': res.value,
            'unit': res.unit,
            'printedRange': res.hasPrintedRange ? {'low': res.printedLow, 'high': res.printedHigh} : null,
            'sampledOn': rec.effectiveDate.toIso8601String(),
            'ageDays': at.difference(rec.effectiveDate).inDays,
            'lab': rec.labName,
            'source': rec.provenance.name,
            'recordId': rec.id,
            'hasOriginal': rec.attachmentId != null,
            if (prev != null) 'previous': {'value': prev.$2.value, 'unit': prev.$2.unit, 'sampledOn': prev.$1.effectiveDate.toIso8601String()},
          };
        }(),
    ]..sort((a, b) => (a['ageDays']! as int).compareTo(b['ageDays']! as int));
  }

  static Map<String, Object?> _document(HealthRecord r, DateTime at) => {
        'id': r.id,
        'kind': r.kind.name,
        'title': r.title,
        'date': r.effectiveDate.toIso8601String(),
        'ageDays': at.difference(r.effectiveDate).inDays,
        'doctor': r.doctor,
        'lab': r.labName,
        'source': r.provenance.name,
        'hasOriginal': r.attachmentId != null,
        'results': [for (final res in r.results) res.toJson()],
      };
}
