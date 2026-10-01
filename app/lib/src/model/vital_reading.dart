/// A reading the patient took at home: blood pressure or blood sugar.
/// Local-only by default (CLAUDE.md #6); shared only when the patient ticks
/// home readings for a doctor, and backed up only on opt-in.
enum VitalKind { bloodPressure, glucose }

enum GlucoseContext {
  fasting('Fasting'),
  afterMeal('After a meal'),
  random('Random'),
  bedtime('Bedtime');

  const GlucoseContext(this.label);
  final String label;
}

class VitalReading {
  const VitalReading({
    required this.id,
    required this.patientId,
    required this.at,
    required this.kind,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.glucose,
    this.context,
  });

  final String id;
  final String patientId;
  final DateTime at;
  final VitalKind kind;

  /// mmHg.
  final int? systolic;
  final int? diastolic;

  /// Beats per minute.
  final int? pulse;

  /// mg/dL.
  final double? glucose;
  final GlucoseContext? context;

  /// "132/84 mmHg · pulse 76" or "112 mg/dL · fasting". States the numbers.
  String get display => kind == VitalKind.bloodPressure
      ? '$systolic/$diastolic mmHg${pulse == null ? '' : ' · pulse $pulse'}'
      : '${glucose == glucose!.roundToDouble() ? glucose!.toStringAsFixed(0) : glucose} mg/dL${context == null ? '' : ' · ${context!.label.toLowerCase()}'}';

  Map<String, Object?> toJson() => {
        'id': id,
        'patientId': patientId,
        'at': at.toIso8601String(),
        'kind': kind.name,
        'sys': systolic,
        'dia': diastolic,
        'pulse': pulse,
        'glucose': glucose,
        'context': context?.name,
      };

  static VitalReading fromJson(Map<String, Object?> j) => VitalReading(
        id: j['id']! as String,
        patientId: j['patientId']! as String,
        at: DateTime.parse(j['at']! as String),
        kind: VitalKind.values.byName(j['kind']! as String),
        systolic: j['sys'] as int?,
        diastolic: j['dia'] as int?,
        pulse: j['pulse'] as int?,
        glucose: (j['glucose'] as num?)?.toDouble(),
        context: j['context'] == null ? null : GlucoseContext.values.byName(j['context']! as String),
      );

  /// Plausibility, not judgement: catches a slipped digit before saving.
  static String? check({int? systolic, int? diastolic, int? pulse, double? glucose}) {
    if (systolic != null && (systolic < 50 || systolic > 300)) return 'The top number should be between 50 and 300.';
    if (diastolic != null && (diastolic < 30 || diastolic > 200)) return 'The bottom number should be between 30 and 200.';
    if (systolic != null && diastolic != null && diastolic >= systolic) return 'The bottom number should be lower than the top one.';
    if (pulse != null && (pulse < 25 || pulse > 250)) return 'Pulse should be between 25 and 250.';
    if (glucose != null && (glucose < 10 || glucose > 800)) return 'Sugar should be between 10 and 800 mg/dL.';
    return null;
  }
}
