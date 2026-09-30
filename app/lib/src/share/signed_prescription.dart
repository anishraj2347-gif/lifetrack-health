import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A prescription written in the doctor app, signed with the doctor device's
/// Ed25519 key (the one its registry certificate names).
///
/// Carries what the Telemedicine Practice Guidelines 2020 require on a
/// prescription: the doctor's name, qualification and registration number.
class SignedPrescription {
  const SignedPrescription({
    required this.patientId,
    required this.doctorRegistryId,
    required this.doctorName,
    required this.qualification,
    required this.registrationNo,
    required this.medicine,
    required this.ingredient,
    required this.morning,
    required this.afternoon,
    required this.night,
    required this.days,
    required this.issuedAt,
    this.note,
    this.signature = const [],
  });

  final String patientId;
  final String doctorRegistryId;
  final String doctorName;
  final String qualification;
  final String registrationNo;
  final String medicine;
  final String? ingredient;
  final int morning;
  final int afternoon;
  final int night;
  final int days;
  final DateTime issuedAt;
  final String? note;
  final List<int> signature;

  Map<String, Object?> _body() => {
        'v': 1,
        'patient': patientId,
        'doctor': doctorRegistryId,
        'doctorName': doctorName,
        'qualification': qualification,
        'reg': registrationNo,
        'medicine': medicine,
        'ingredient': ingredient,
        'dose': [morning, afternoon, night],
        'days': days,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'note': note,
      };

  List<int> get signedBytes => utf8.encode(jsonEncode(_body()));

  Future<SignedPrescription> signedWith(SimpleKeyPair doctorSigningKey) async {
    final sig = await Ed25519().sign(signedBytes, keyPair: doctorSigningKey);
    return SignedPrescription.fromJson({..._body(), 'signature': base64Encode(sig.bytes)});
  }

  Future<bool> verifies(List<int> doctorSigningPublicKey) =>
      Ed25519().verify(signedBytes, signature: Signature(signature, publicKey: SimplePublicKey(doctorSigningPublicKey, type: KeyPairType.ed25519)));

  Map<String, Object?> toJson() => {..._body(), 'signature': base64Encode(signature)};

  static SignedPrescription fromJson(Map<String, Object?> j) {
    final dose = (j['dose']! as List).cast<int>();
    return SignedPrescription(
      patientId: j['patient']! as String,
      doctorRegistryId: j['doctor']! as String,
      doctorName: j['doctorName']! as String,
      qualification: j['qualification']! as String,
      registrationNo: j['reg']! as String,
      medicine: j['medicine']! as String,
      ingredient: j['ingredient'] as String?,
      morning: dose[0],
      afternoon: dose[1],
      night: dose[2],
      days: j['days']! as int,
      issuedAt: DateTime.parse(j['issuedAt']! as String),
      note: j['note'] as String?,
      signature: j['signature'] == null ? const [] : base64Decode(j['signature']! as String),
    );
  }
}
