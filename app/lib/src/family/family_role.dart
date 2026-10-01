/// Who a family member is *to the head of family* — the phone owner, whose
/// profile the others are kept under. Stored as [name] in `Custody.relation`
/// (older values like "spouse" and "son" are the same names).
///
/// The role is a label for the overview. It never widens authority: a child
/// under 18 can be added only by their parent (son or daughter of the head),
/// and every adult agrees in person — CLAUDE.md #14.
enum FamilyRole {
  grandfather('Grandfather', -2),
  grandmother('Grandmother', -2),
  father('Father', -1),
  mother('Mother', -1),
  fatherInLaw('Father-in-law', -1),
  motherInLaw('Mother-in-law', -1),
  uncle('Uncle', -1),
  aunt('Aunt', -1),
  wife('Wife', 0),
  husband('Husband', 0),
  spouse('Spouse', 0),
  brother('Brother', 0),
  sister('Sister', 0),
  brotherInLaw('Brother-in-law', 0),
  sisterInLaw('Sister-in-law', 0),
  cousin('Cousin', 0),
  son('Son', 1),
  daughter('Daughter', 1),
  sonInLaw('Son-in-law', 1),
  daughterInLaw('Daughter-in-law', 1),
  nephew('Nephew', 1),
  niece('Niece', 1),
  grandson('Grandson', 2),
  granddaughter('Granddaughter', 2),
  other('Other relative', 0);

  const FamilyRole(this.label, this.generation);
  final String label;

  /// Relative to the head: −2 grandparents … 0 the head's own generation … +2 grandchildren.
  final int generation;

  /// A child under 18 is added only by their parent.
  static const forChild = [son, daughter];

  /// Roles shown when adding an adult, in the order of the picker.
  static const forAdult = [
    father, mother, wife, husband, brother, sister, son, daughter,
    grandfather, grandmother, fatherInLaw, motherInLaw, sonInLaw, daughterInLaw,
    brotherInLaw, sisterInLaw, grandson, granddaughter, uncle, aunt, nephew, niece, cousin, other,
  ];

  static FamilyRole? parse(String relation) => FamilyRole.values.where((r) => r.name == relation).firstOrNull;

  /// "father-in-law" for a sentence; unknown text is shown as it was typed.
  static String describe(String relation) => parse(relation)?.label.toLowerCase() ?? relation;

  static String generationTitle(int g) => switch (g) {
        -2 => 'Grandparents',
        -1 => 'Parents and elders',
        0 => 'Head of family',
        1 => 'Children',
        _ => 'Grandchildren',
      };
}
