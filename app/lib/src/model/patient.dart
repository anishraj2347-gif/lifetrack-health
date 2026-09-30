import 'package:lifetrack_protocol/lifetrack_protocol.dart' show IdentityAttestation;

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
    this.verification,
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

  /// DigiLocker's confirmation of name, date of birth and gender, signed by
  /// the LifeTrack service. Null for profiles made before verification.
  final IdentityAttestation? verification;
  bool get isVerified => verification != null;

  Patient withAbha(Abha? a) => Patient(id: id, name: name, dateOfBirth: dateOfBirth, sex: sex, pregnant: pregnant, abha: a, verification: verification);

  /// Takes name, date of birth and sex from [v] — a verified profile shows
  /// exactly what DigiLocker confirmed.
  Patient withVerification(IdentityAttestation v) => Patient(
        id: id,
        name: v.name,
        dateOfBirth: v.dateOfBirth,
        sex: sexFromGender(v.gender),
        pregnant: pregnant,
        abha: abha,
        verification: v,
      );

  static Sex sexFromGender(String? g) => switch (g) { 'F' => Sex.female, 'M' => Sex.male, _ => Sex.unspecified };

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
        if (verification != null) 'verification': verification!.toJson(),
      };

  static Patient fromJson(Map<String, Object?> j) => Patient(
        id: j['id']! as String,
        name: j['name']! as String,
        dateOfBirth: DateTime.parse(j['dob']! as String),
        sex: Sex.values.byName(j['sex']! as String),
        pregnant: (j['pregnant'] as bool?) ?? false,
        abha: j['abha'] == null ? null : Abha.fromJson((j['abha']! as Map).cast()),
        verification: j['verification'] == null ? null : IdentityAttestation.fromJson((j['verification']! as Map).cast()),
      );
}
