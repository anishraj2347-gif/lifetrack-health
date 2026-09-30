import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'doctor_certificate.dart';

/// How a person's identity was checked. Aadhaar through DigiLocker for
/// everyone; a birth certificate from a verified parent's DigiLocker only
/// for a newborn who has no Aadhaar yet.
enum IdentityMethod {
  aadhaarDigiLocker,
  birthCertificateDigiLocker;

  String get label => switch (this) {
        aadhaarDigiLocker => 'Aadhaar via DigiLocker',
        birthCertificateDigiLocker => 'Birth certificate via parent\'s DigiLocker',
      };
}

/// The LifeTrack service's statement that DigiLocker confirmed these
/// details, signed with the registry key the app already pins. It holds no
/// Aadhaar number and no document — only what the profile needs, and a
/// keyed hash of the DigiLocker identity so one person gets one profile.
class IdentityAttestation {
  const IdentityAttestation({
    required this.method,
    required this.name,
    required this.dateOfBirth,
    required this.gender,
    required this.subjectHash,
    required this.verifiedAt,
    this.parentSubjectHash,
    this.signature = const [],
  });

  final IdentityMethod method;
  final String name;
  final DateTime dateOfBirth;

  /// `F`, `M`, `T`, or null when DigiLocker did not say.
  final String? gender;

  /// HMAC of the DigiLocker identity under a server secret: equal for the
  /// same person, meaningless outside LifeTrack, not reversible.
  final String subjectHash;
  final DateTime verifiedAt;

  /// For a newborn: the verified parent whose DigiLocker held the certificate.
  final String? parentSubjectHash;
  final List<int> signature;

  Map<String, Object?> _body() => {
        'v': 1,
        'method': method.name,
        'name': name,
        'dob': dateOfBirth.toIso8601String().substring(0, 10),
        'gender': gender,
        'subject': subjectHash,
        'verifiedAt': verifiedAt.toUtc().toIso8601String(),
        if (parentSubjectHash != null) 'parent': parentSubjectHash,
      };

  List<int> get signedBytes => utf8.encode(jsonEncode(_body()));

  Future<IdentityAttestation> signedWith(SimpleKeyPair registryKey) async {
    final sig = await Ed25519().sign(signedBytes, keyPair: registryKey);
    return IdentityAttestation.fromJson({..._body(), 'signature': base64Encode(sig.bytes)});
  }

  /// True when one of [trust]'s registry keys signed exactly these details.
  Future<bool> verifies(RegistryTrust trust) async {
    for (final k in trust.keys) {
      if (await Ed25519().verify(signedBytes, signature: Signature(signature, publicKey: k))) return true;
    }
    return false;
  }

  Map<String, Object?> toJson() => {..._body(), 'signature': base64Encode(signature)};

  static IdentityAttestation fromJson(Map<String, Object?> j) => IdentityAttestation(
        method: IdentityMethod.values.byName(j['method']! as String),
        name: j['name']! as String,
        dateOfBirth: DateTime.parse(j['dob']! as String),
        gender: j['gender'] as String?,
        subjectHash: j['subject']! as String,
        verifiedAt: DateTime.parse(j['verifiedAt']! as String),
        parentSubjectHash: j['parent'] as String?,
        signature: j['signature'] == null ? const [] : base64Decode(j['signature']! as String),
      );
}
