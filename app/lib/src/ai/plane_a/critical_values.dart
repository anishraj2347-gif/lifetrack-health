import '../insight.dart';

/// Critical-value thresholds (audit ruling C: approved, constrained).
///
/// Constraints this table exists to satisfy:
///  1. A published, citable table shaped like `referenceRanges`, unit-gated
///     and deterministic.
///  2. Escalation changes only `severity` and `action` — never the wording
///     of `finding`.
///  3. Exactly three levels: discussSoon (out of range), contactDoctorToday,
///     urgentCare. A continuous urgency gradient is Tier 2.
///
/// Values follow commonly published laboratory critical-limit lists. Before a
/// pilot this table must be replaced by the partner laboratory's own
/// published list and cited here by name and revision.
class CriticalLimit {
  const CriticalLimit({required this.analyte, required this.unit, this.todayBelow, this.todayAbove, this.urgentBelow, this.urgentAbove});
  final String analyte;
  final String unit;
  final double? todayBelow;
  final double? todayAbove;
  final double? urgentBelow;
  final double? urgentAbove;

  Severity? classify(double v) {
    if ((urgentBelow != null && v < urgentBelow!) || (urgentAbove != null && v > urgentAbove!)) {
      return Severity.urgentCare;
    }
    if ((todayBelow != null && v < todayBelow!) || (todayAbove != null && v > todayAbove!)) {
      return Severity.contactDoctorToday;
    }
    return null;
  }
}

const criticalLimits = <CriticalLimit>[
  CriticalLimit(analyte: 'glucose_fasting', unit: 'mg/dL', todayBelow: 54, todayAbove: 300, urgentBelow: 40, urgentAbove: 450),
  CriticalLimit(analyte: 'haemoglobin', unit: 'g/dL', todayBelow: 8.0, urgentBelow: 7.0, urgentAbove: 20.0),
  CriticalLimit(analyte: 'creatinine', unit: 'mg/dL', todayAbove: 3.0, urgentAbove: 5.0),
  CriticalLimit(analyte: 'hba1c', unit: '%', todayAbove: 12.0),
];

/// The route-to-a-person sentence for each severity. The only place urgency
/// changes wording.
String actionFor(Severity s) => switch (s) {
      Severity.note => 'Worth showing your doctor at your next routine visit.',
      Severity.discussSoon => 'Discuss this result with your doctor at your next visit.',
      Severity.contactDoctorToday => 'Contact your doctor today about this result.',
      Severity.urgentCare =>
        'Seek medical care now. If you feel unwell, go to the nearest emergency department or call 108.',
    };
