import '../../model/patient.dart';

/// A reference interval. Either bound may be absent: HDL has only a floor,
/// LDL only a ceiling. Absent is `null`, never a sentinel like 999 — a
/// sentinel gets printed to a patient as a clinical bound, and exported as one.
class ReferenceRange {
  const ReferenceRange({
    required this.analyte,
    required this.unit,
    this.low,
    this.high,
    this.population = 'adults',
    this.sex,
    this.minAge = 18,
    this.excludesPregnancy = false,
  }) : assert(low != null || high != null);

  final String analyte;
  final String unit;
  final double? low;
  final double? high;
  final String population;
  final Sex? sex;
  final int minAge;

  /// Pregnancy shifts this interval; for a pregnant patient it is not applied.
  final bool excludesPregnancy;

  bool matchesUnit(String u) => u.trim().toLowerCase() == unit.toLowerCase();

  /// Only meaningful after [matchesUnit]. Callers must check the unit first —
  /// a unit mismatch is "not checked", never "out of range".
  bool contains(double v) => (low == null || v >= low!) && (high == null || v <= high!);

  bool isAbove(double v) => high != null && v > high!;

  /// Patient-facing description, e.g. "70–99 mg/dL", "50 mg/dL or above".
  /// The one formatter every screen uses.
  String describe() {
    String f(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toString();
    if (low != null && high != null) return '${f(low!)}–${f(high!)} $unit';
    if (low != null) return '${f(low!)} $unit or above';
    return '${f(high!)} $unit or below';
  }
}

/// Source: consensus adult intervals as printed by Indian reference labs and
/// ADA 2026 Standards of Care for glycaemic markers. Adults only — a child
/// gets `null` and the result is reported as not checked.
const referenceRanges = <ReferenceRange>[
  ReferenceRange(analyte: 'glucose_fasting', unit: 'mg/dL', low: 70, high: 99),
  ReferenceRange(analyte: 'hba1c', unit: '%', high: 5.6),
  ReferenceRange(analyte: 'total_cholesterol', unit: 'mg/dL', high: 199),
  ReferenceRange(analyte: 'ldl', unit: 'mg/dL', high: 99),
  ReferenceRange(analyte: 'hdl', unit: 'mg/dL', low: 50, sex: Sex.female, population: 'adult women'),
  ReferenceRange(analyte: 'hdl', unit: 'mg/dL', low: 40, sex: Sex.male, population: 'adult men'),
  ReferenceRange(analyte: 'triglycerides', unit: 'mg/dL', high: 149),
  ReferenceRange(analyte: 'haemoglobin', unit: 'g/dL', low: 12.0, high: 15.5, sex: Sex.female, population: 'adult women', excludesPregnancy: true),
  ReferenceRange(analyte: 'haemoglobin', unit: 'g/dL', low: 13.5, high: 17.5, sex: Sex.male, population: 'adult men'),
  ReferenceRange(analyte: 'creatinine', unit: 'mg/dL', low: 0.59, high: 1.04, sex: Sex.female, population: 'adult women', excludesPregnancy: true),
  ReferenceRange(analyte: 'creatinine', unit: 'mg/dL', low: 0.74, high: 1.35, sex: Sex.male, population: 'adult men'),
  ReferenceRange(analyte: 'tsh', unit: 'mIU/L', low: 0.4, high: 4.0, excludesPregnancy: true),
  ReferenceRange(analyte: 'ferritin', unit: 'ng/mL', low: 15, high: 150, sex: Sex.female, population: 'adult women'),
  ReferenceRange(analyte: 'ferritin', unit: 'ng/mL', low: 30, high: 400, sex: Sex.male, population: 'adult men'),
];

/// Human names for analyte keys.
const analyteNames = <String, String>{
  'glucose_fasting': 'Fasting glucose',
  'hba1c': 'HbA1c',
  'total_cholesterol': 'Total cholesterol',
  'ldl': 'LDL cholesterol',
  'hdl': 'HDL cholesterol',
  'triglycerides': 'Triglycerides',
  'haemoglobin': 'Haemoglobin',
  'creatinine': 'Creatinine',
  'tsh': 'TSH',
  'ferritin': 'Ferritin',
  'vitamin_d': 'Vitamin D',
};

String analyteName(String key) => analyteNames[key] ?? key;

enum RangeLookup { found, noRange, notApplicable }

/// The interval that applies to [patient] at [at], or why there is none.
(RangeLookup, ReferenceRange?) referenceRangeFor(String analyte, Patient patient, DateTime at) {
  final candidates = referenceRanges.where((r) => r.analyte == analyte).toList();
  if (candidates.isEmpty) return (RangeLookup.noRange, null);
  if (patient.ageAt(at) < 18) return (RangeLookup.notApplicable, null);
  final forSex = candidates.where((r) => r.sex == null || r.sex == patient.sex).toList();
  // Sex-specific interval and sex unspecified: do not pick one.
  if (forSex.isEmpty || (patient.sex == Sex.unspecified && forSex.any((r) => r.sex != null))) {
    return (RangeLookup.notApplicable, null);
  }
  final range = forSex.first;
  if (patient.pregnant && range.excludesPregnancy) return (RangeLookup.notApplicable, null);
  return (RangeLookup.found, range);
}
