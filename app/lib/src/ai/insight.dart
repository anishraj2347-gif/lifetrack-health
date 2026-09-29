/// The output contract for every patient-facing clinical statement
/// (CLAUDE.md #8, #9). Screens render an [Insight]; they never derive one.
enum Severity {
  /// Movement in a good direction, or context worth seeing. Never red.
  note,

  /// Outside the reference interval. Raise at the next visit.
  discussSoon,

  /// On the critical-value table's first tier.
  contactDoctorToday,

  /// On the critical-value table's second tier.
  urgentCare,
}

enum InsightKind { outOfRange, critical, trend, medication }

class Insight {
  const Insight({
    required this.kind,
    required this.severity,
    required this.finding,
    required this.action,
    required this.evidence,
    this.analyte,
  });

  final InsightKind kind;
  final Severity severity;

  /// States position or movement, then stops. No interpretation.
  final String finding;

  /// Always a route to a person: a doctor, a pharmacist, emergency care.
  final String action;

  /// Record ids the finding rests on.
  final List<String> evidence;
  final String? analyte;

  static const disclaimer =
      'This compares your numbers with published ranges. It is not a medical opinion — your doctor decides what it means.';
}

/// Why a result could not be checked. Rendered, never swallowed: an unchecked
/// result shown as "nothing stands out" is an all-clear nobody issued.
enum NotCheckedReason { noRangeForAnalyte, unitMismatch, notApplicableToPatient }

class NotChecked {
  const NotChecked({required this.recordId, required this.analyte, required this.value, required this.unit, required this.reason});
  final String recordId;
  final String analyte;
  final double value;
  final String unit;
  final NotCheckedReason reason;

  String get explanation => switch (reason) {
        NotCheckedReason.noRangeForAnalyte => 'LifeTrack has no reference range for this test.',
        NotCheckedReason.unitMismatch => 'Reported in $unit, which LifeTrack cannot compare with its range.',
        NotCheckedReason.notApplicableToPatient =>
          'The standard adult range does not apply to you (age or pregnancy), so it was not compared.',
      };
}

class InsightRun {
  const InsightRun({required this.insights, required this.unresolved, required this.dropped});
  final List<Insight> insights;
  final List<NotChecked> unresolved;

  /// Insights removed by the banned-phrase filter. Counted so a regression in
  /// wording shows up in tests rather than as silently missing findings.
  final int dropped;

  /// True only when every result was checked and none produced a finding.
  bool get allChecked => unresolved.isEmpty;
}
