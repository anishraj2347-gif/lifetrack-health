/// The facts a doctor needs first, kept apart from documents: they change
/// rarely, the patient states them, and the Summary level leads with them.
class Allergy {
  const Allergy({required this.substance, this.reaction});
  final String substance;
  final String? reaction;

  Map<String, Object?> toJson() => {'substance': substance, 'reaction': reaction};
  static Allergy fromJson(Map<String, Object?> j) =>
      Allergy(substance: j['substance']! as String, reaction: j['reaction'] as String?);
}

class Condition {
  const Condition({required this.name, this.sinceYear});
  final String name;
  final int? sinceYear;

  Map<String, Object?> toJson() => {'name': name, 'since': sinceYear};
  static Condition fromJson(Map<String, Object?> j) =>
      Condition(name: j['name']! as String, sinceYear: j['since'] as int?);
}

enum Relation { mother, father, sister, brother, grandparent, child, other }

/// Family history as the PATIENT knows it — the patient's own statement, not
/// the relative's record, so it needs no relative's consent (legal review,
/// 30 Sep 2026). Always shown to the doctor as "patient-reported".
class FamilyIllness {
  const FamilyIllness({required this.relation, required this.condition, this.ageAtOnset, this.deceasedAtAge});
  final Relation relation;
  final String condition;
  final int? ageAtOnset;
  final int? deceasedAtAge;

  Map<String, Object?> toJson() => {
        'relation': relation.name,
        'condition': condition,
        'onset': ageAtOnset,
        'died': deceasedAtAge,
      };
  static FamilyIllness fromJson(Map<String, Object?> j) => FamilyIllness(
        relation: Relation.values.byName(j['relation']! as String),
        condition: j['condition']! as String,
        ageAtOnset: j['onset'] as int?,
        deceasedAtAge: j['died'] as int?,
      );
}

class ClinicalProfile {
  const ClinicalProfile({
    this.allergies = const [],
    this.conditions = const [],
    this.familyIllnesses = const [],
    this.updatedAt,
  });

  final List<Allergy> allergies;
  final List<Condition> conditions;
  final List<FamilyIllness> familyIllnesses;

  /// Shown to the doctor as "Last updated by patient on …".
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
        'allergies': [for (final a in allergies) a.toJson()],
        'conditions': [for (final c in conditions) c.toJson()],
        'family': [for (final f in familyIllnesses) f.toJson()],
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static ClinicalProfile fromJson(Map<String, Object?> j) => ClinicalProfile(
        allergies: [for (final a in (j['allergies'] as List?) ?? const []) Allergy.fromJson((a as Map).cast())],
        conditions: [for (final c in (j['conditions'] as List?) ?? const []) Condition.fromJson((c as Map).cast())],
        familyIllnesses: [for (final f in (j['family'] as List?) ?? const []) FamilyIllness.fromJson((f as Map).cast())],
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt']! as String),
      );
}
