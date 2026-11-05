import '../insight.dart';

/// Danger limits for lab values, in one table (audit ruling C: approved,
/// constrained). What `CriticalCheck` reads, on every saved value.
///
/// Constraints this table exists to satisfy:
///  1. Unit-gated and deterministic: every limit is in one canonical [unit],
///     and [forms] lists the units that convert to it. Anything else is not
///     guessed at silently.
///  2. Escalation changes only `severity` and `action` — never the wording of
///     a range finding.
///  3. Exactly three levels: discussSoon (out of range), contactDoctorToday,
///     urgentCare. A continuous urgency gradient is Tier 2.
///
/// These are danger limits, not reference intervals: they sit far outside
/// what is usual at any age, and nothing here says a value is in or out of
/// range. That is why they may be applied to a child or in pregnancy (#10
/// forbids adult *reference intervals* there), with one exception: a high
/// side marked [CriticalLimit.highSideFromAge] is usual in the first year of
/// life, so a baby's value is "not checked", never compared.
///
/// NO DOCTOR HAS APPROVED THESE VALUES. They are conservative, commonly cited
/// figures. Before a pilot they must be reviewed by a clinician and replaced
/// by the partner laboratory's own published list, cited here by name and
/// revision. Each entry says where its number comes from; `VERIFY WITH
/// CLINICIAN` marks every one that is not settled.
class UnitForm {
  const UnitForm(this.spellings, {this.factor = 1, this.offset = 0});

  /// As [normaliseUnit] leaves them.
  final Set<String> spellings;
  final double factor;
  final double offset;

  double toCanonical(double v) => v * factor + offset;
  bool get isCanonical => factor == 1 && offset == 0;
}

class CriticalLimit {
  const CriticalLimit({
    required this.analytes,
    required this.unit,
    required this.forms,
    required this.plausible,
    this.todayBelow,
    this.todayAbove,
    this.urgentBelow,
    this.urgentAbove,
    this.highSideFromAge = 0,
  });

  /// One limit can cover several keys: all four kinds of glucose.
  final Set<String> analytes;

  /// The canonical unit every limit below is written in.
  final String unit;
  final List<UnitForm> forms;

  /// Canonical bounds a real result can have. Used only when the unit is
  /// missing or unknown, to rule out readings of the number that cannot be.
  final (double, double) plausible;

  final double? todayBelow;
  final double? todayAbove;
  final double? urgentBelow;
  final double? urgentAbove;

  /// Below this age in whole years the high side is not applied.
  final int highSideFromAge;

  /// [v] is in [unit].
  Severity? classify(double v, {bool highSide = true}) {
    if ((urgentBelow != null && v < urgentBelow!) || (highSide && urgentAbove != null && v > urgentAbove!)) {
      return Severity.urgentCare;
    }
    if ((todayBelow != null && v < todayBelow!) || (highSide && todayAbove != null && v > todayAbove!)) {
      return Severity.contactDoctorToday;
    }
    return null;
  }

  /// The bound [v] crossed at [s], for the sentence that states it.
  (String, double) crossed(double v, Severity s) {
    final (low, high) = s == Severity.urgentCare ? (urgentBelow, urgentAbove) : (todayBelow, todayAbove);
    return low != null && v < low ? ('below', low) : ('above', high!);
  }
}

const _mgdl = UnitForm({'mg/dl', 'mg%', 'mgs/dl', 'mgm/dl'});
const _gdl = UnitForm({'g/dl', 'gm/dl', 'gms/dl', 'gram/dl', 'g%', 'gm%', 'gms%', 'gram%'});
const _gl = UnitForm({'g/l', 'gm/l', 'gms/l'}, factor: 0.1);
const _mmol = UnitForm({'mmol/l', 'meq/l'});
const _perUl = UnitForm({'/ul', '/cumm', '/cmm', '/mm3', 'ul', 'cumm', 'cmm', 'mm3'});
const _thousands = UnitForm({'103/ul', '10e3/ul', '103/cumm', '103/mm3', '109/l', '10e9/l', 'thou/ul', 'thou/cumm', 'thou/mm3', 'thousand/ul', 'thousand/cumm', 'k/ul'}, factor: 1000);
const _lakhs = UnitForm({'lakh/cumm', 'lakhs/cumm', 'lac/cumm', 'lacs/cumm', 'lakh/ul', 'lakhs/ul', 'lac/ul', 'lacs/ul', 'lakh/mm3', 'lakhs/mm3'}, factor: 100000);

const criticalLimits = <CriticalLimit>[
  // Low side: ADA Standards of Care (Glycemic Goals and Hypoglycemia), level 2
  // hypoglycaemia is below 54 mg/dL. High side: common lab critical list;
  // varies. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'glucose', 'glucose_fasting', 'glucose_pp', 'glucose_random'},
    unit: 'mg/dL',
    forms: [_mgdl, UnitForm({'mmol/l'}, factor: 18)],
    plausible: (10, 2000),
    todayAbove: 300,
    urgentBelow: 54,
    urgentAbove: 450,
  ),
  // Common lab critical list; varies (urgent limits are usually 2.5–3.0 and
  // 6.0–6.5). A haemolysed sample raises it; newborn values run higher, so
  // the high side starts at age 1. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'potassium'},
    unit: 'mmol/L',
    forms: [_mmol],
    plausible: (1, 12),
    todayBelow: 3.0,
    todayAbove: 5.5,
    urgentBelow: 2.5,
    urgentAbove: 6.0,
    highSideFromAge: 1,
  ),
  // Common lab critical list; varies. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'sodium'},
    unit: 'mmol/L',
    forms: [_mmol],
    plausible: (90, 200),
    todayBelow: 125,
    todayAbove: 155,
    urgentBelow: 120,
    urgentAbove: 160,
  ),
  // Total calcium. Common lab critical list; varies. Not corrected for
  // albumin. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'calcium'},
    unit: 'mg/dL',
    forms: [_mgdl, UnitForm({'mmol/l'}, factor: 4.0), UnitForm({'meq/l'}, factor: 2.0)],
    plausible: (3, 20),
    todayBelow: 7.5,
    todayAbove: 12.0,
    urgentBelow: 6.5,
    urgentAbove: 13.0,
  ),
  // Common lab critical list; varies (low urgent limits run from 10,000 to
  // 50,000). The high side is a same-day prompt only. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'platelets'},
    unit: '/µL',
    forms: [_perUl, _thousands, _lakhs],
    plausible: (500, 3000000),
    todayBelow: 50000,
    todayAbove: 1000000,
    urgentBelow: 20000,
  ),
  // Common lab critical list; varies. Newborn counts run high, so the high
  // side starts at age 1. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'wbc'},
    unit: '/µL',
    forms: [_perUl, _thousands],
    plausible: (100, 500000),
    todayBelow: 2000,
    todayAbove: 30000,
    urgentBelow: 1000,
    urgentAbove: 50000,
    highSideFromAge: 1,
  ),
  // Common lab critical list; varies. Newborn values run high, so the high
  // side starts at age 1. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'haemoglobin'},
    unit: 'g/dL',
    forms: [_gdl, _gl],
    plausible: (1, 26),
    todayBelow: 8.0,
    urgentBelow: 7.0,
    urgentAbove: 20.0,
    highSideFromAge: 1,
  ),
  // Common lab critical list; varies. A person on dialysis sits above these
  // every time. VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'creatinine'},
    unit: 'mg/dL',
    forms: [_mgdl, UnitForm({'umol/l'}, factor: 1 / 88.4)],
    plausible: (0.05, 30),
    todayAbove: 3.0,
    urgentAbove: 5.0,
  ),
  // No published critical limit that this project can cite: a same-day prompt
  // kept from the first table. mmol/mol by the NGSP/IFCC master equation.
  // VERIFY WITH CLINICIAN.
  CriticalLimit(
    analytes: {'hba1c'},
    unit: '%',
    forms: [UnitForm({'%'}), UnitForm({'mmol/mol'}, factor: 0.09148, offset: 2.152)],
    plausible: (2, 25),
    todayAbove: 12.0,
  ),
];

/// Lowercase, no spaces, one spelling of each sign, so "Gm %", "gm%" and
/// "x10^3 /µL" compare with the [UnitForm] sets.
String normaliseUnit(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp('[µμ]'), 'u')
    .replaceAll('×', 'x')
    .replaceAll('³', '3')
    .replaceAll('⁶', '6')
    .replaceAll('⁹', '9')
    .replaceAll('^', '')
    .replaceAll('cu.mm', 'cumm')
    .replaceAll('cells', '')
    .replaceAll(RegExp(r'[.,;:)]+$'), '')
    .replaceFirst(RegExp(r'^x(?=\d)'), '');

/// The route-to-a-person sentence for each severity. The only place urgency
/// changes wording.
String actionFor(Severity s) => switch (s) {
      Severity.note => 'Worth showing your doctor at your next routine visit.',
      Severity.discussSoon => 'Discuss this result with your doctor at your next visit.',
      Severity.contactDoctorToday => 'Contact your doctor today about this result.',
      Severity.urgentCare =>
        'Seek medical care now. If you feel unwell, go to the nearest emergency department or call 108.',
    };
