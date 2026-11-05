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

/// What the "no known allergies" choice says, on the card and to a doctor.
/// Said on purpose, unlike an empty list.
const noKnownAllergies = 'No known allergies';

class ClinicalProfile {
  const ClinicalProfile({
    this.allergies = const [],
    this.noneKnown = false,
    this.conditions = const [],
    this.familyIllnesses = const [],
    this.updatedAt,
  });

  static const maxTextLength = 80;

  /// The one list of allergies: the Emergency ID's line ([cardLine]) and the
  /// clinical share are both made from it. Empty says "not recorded", never
  /// "none"; [noneKnown] is the statement that there are none.
  final List<Allergy> allergies;

  /// The patient said there are no known allergies.
  final bool noneKnown;
  final List<Condition> conditions;
  final List<FamilyIllness> familyIllnesses;

  /// Shown to the doctor as "Last updated by patient on …".
  final DateTime? updatedAt;

  /// The list as the Emergency ID's one bounded field holds it.
  String cardLine(int maxLength) {
    if (allergies.isEmpty) return noneKnown ? noKnownAllergies : '';
    final names = [for (final a in allergies) a.substance];
    for (var shown = names.length; shown > 0; shown--) {
      final rest = names.length - shown;
      final line = names.take(shown).join(', ') + (rest == 0 ? '' : ' +$rest more');
      if (line.length <= maxLength) return line;
    }
    return '${names.first.substring(0, maxLength - 12)}… +${names.length - 1} more';
  }

  /// This profile after the card's allergy line was edited to [line]. An
  /// allergy still named keeps its reaction; those the card could only count
  /// ("+2 more") are kept.
  ClinicalProfile withCardLine(String line, DateTime at) {
    final text = line.trim();
    final more = RegExp(r'\s*\+(\d+) more$').firstMatch(text);
    final hidden = more == null ? 0 : int.parse(more.group(1)!);
    final named = [
      for (final n in text.substring(0, more?.start ?? text.length).split(RegExp(r'[,;\n]')))
        if (n.trim().isNotEmpty && n.trim() != noKnownAllergies) n.trim(),
    ];
    Allergy keep(String name) => allergies.where((a) => a.substance.toLowerCase() == name.toLowerCase()).firstOrNull ?? Allergy(substance: name);
    return ClinicalProfile(
      allergies: [...named.map(keep), ...allergies.skip(allergies.length - hidden.clamp(0, allergies.length))],
      noneKnown: text == noKnownAllergies,
      conditions: conditions,
      familyIllnesses: familyIllnesses,
      updatedAt: at,
    );
  }

  Map<String, Object?> toJson() => {
        'allergies': [for (final a in allergies) a.toJson()],
        if (noneKnown) 'noneKnown': true,
        'conditions': [for (final c in conditions) c.toJson()],
        'family': [for (final f in familyIllnesses) f.toJson()],
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static ClinicalProfile fromJson(Map<String, Object?> j) => ClinicalProfile(
        allergies: [for (final a in (j['allergies'] as List?) ?? const []) Allergy.fromJson((a as Map).cast())],
        noneKnown: (j['noneKnown'] as bool?) ?? false,
        conditions: [for (final c in (j['conditions'] as List?) ?? const []) Condition.fromJson((c as Map).cast())],
        familyIllnesses: [for (final f in (j['family'] as List?) ?? const []) FamilyIllness.fromJson((f as Map).cast())],
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt']! as String),
      );
}
