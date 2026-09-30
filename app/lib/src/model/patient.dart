import 'abha.dart';

/// The demographics a reference interval depends on.
///
/// Carried per patient, never as a global: the moment a second profile exists
/// (family linking, Phase 3) a static would apply one person's age and sex to
/// another person's results.
enum Sex { female, male, unspecified }

class Patient {
  const Patient({
    required this.id,
    required this.name,
    required this.dateOfBirth,
    required this.sex,
    this.pregnant = false,
    this.abha,
  });

  final String id;
  final String name;
  final DateTime dateOfBirth;
  final Sex sex;

  /// Pregnancy changes several intervals (haemoglobin, TSH, creatinine). When
  /// it is true, Plane A declines to apply a non-pregnant adult interval and
  /// reports the result as not checked rather than guessing.
  final bool pregnant;

  /// Optional. Everything in LifeTrack works without it.
  final Abha? abha;

  Patient withAbha(Abha? a) => Patient(id: id, name: name, dateOfBirth: dateOfBirth, sex: sex, pregnant: pregnant, abha: a);

  /// Age in whole years at [at]. Takes the clock explicitly — see
  /// CLAUDE.md "two clocks": a function that reads wall time internally
  /// cannot be tested deterministically.
  int ageAt(DateTime at) {
    var years = at.year - dateOfBirth.year;
    final hadBirthday = at.month > dateOfBirth.month ||
        (at.month == dateOfBirth.month && at.day >= dateOfBirth.day);
    if (!hadBirthday) years -= 1;
    return years;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'dob': dateOfBirth.toIso8601String(),
        'sex': sex.name,
        'pregnant': pregnant,
        if (abha != null) 'abha': abha!.toJson(),
      };

  static Patient fromJson(Map<String, Object?> j) => Patient(
        id: j['id']! as String,
        name: j['name']! as String,
        dateOfBirth: DateTime.parse(j['dob']! as String),
        sex: Sex.values.byName(j['sex']! as String),
        pregnant: (j['pregnant'] as bool?) ?? false,
        abha: j['abha'] == null ? null : Abha.fromJson((j['abha']! as Map).cast()),
      );
}
