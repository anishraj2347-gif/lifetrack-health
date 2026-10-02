import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A doctor device's identity, signed by the LifeTrack doctor registry after
/// its licence check (NMC / state council / HPR, plus manual review).
///
/// The doctor app shows it as a QR; the patient's phone scans and verifies it
/// before offering to share anything (CLAUDE.md #1a, #15). A patient-shown QR
/// was rejected because anyone who photographs it can redeem it.
class DoctorCertificate {
  const DoctorCertificate({
    required this.registryId,
    required this.name,
    required this.speciality,
    required this.council,
    required this.registrationNo,
    required this.encryptionKey,
    required this.signingKey,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
  });

  /// `NMC-…`, `DMC-…`: the id grants are issued to (`doctor:<registryId>`).
  final String registryId;
  final String name;
  final String speciality;
  final String council;
  final String registrationNo;

  /// X25519 public key: shares are encrypted to it.
  final List<int> encryptionKey;

  /// Ed25519 public key: the doctor signs prescriptions with its pair.
  final List<int> signingKey;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// The registry's Ed25519 signature over [signedBytes].
  final List<int> signature;

  /// Short stable id of the encryption key; what a grant is bound to.
  Future<String> keyId() async {
    final h = await Sha256().hash(encryptionKey);
    return h.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> get signedBytes => utf8.encode(jsonEncode(_body()));

  Map<String, Object?> _body() => {
        'v': 1,
        'id': registryId,
        'name': name,
        'speciality': speciality,
        'council': council,
        'reg': registrationNo,
        'enc': base64Encode(encryptionKey),
        'sig': base64Encode(signingKey),
        'iat': issuedAt.toUtc().toIso8601String(),
        'exp': expiresAt.toUtc().toIso8601String(),
      };

  /// What the doctor app puts in its QR.
  String encode() => base64Url.encode(utf8.encode(jsonEncode({..._body(), 'rsig': base64Encode(signature)})));

  static DoctorCertificate decode(String qr) {
    final Map<String, Object?> j;
    try {
      j = (jsonDecode(utf8.decode(base64Url.decode(qr.trim()))) as Map).cast();
    } on FormatException {
      throw const CertificateRejected(CertificateProblem.malformed);
    }
    if (j['v'] != 1) throw const CertificateRejected(CertificateProblem.malformed);
    return DoctorCertificate(
      registryId: j['id']! as String,
      name: j['name']! as String,
      speciality: j['speciality']! as String,
      council: j['council']! as String,
      registrationNo: j['reg']! as String,
      encryptionKey: base64Decode(j['enc']! as String),
      signingKey: base64Decode(j['sig']! as String),
      issuedAt: DateTime.parse(j['iat']! as String),
      expiresAt: DateTime.parse(j['exp']! as String),
      signature: base64Decode(j['rsig']! as String),
    );
  }
}

enum CertificateProblem { malformed, untrustedRegistry, badSignature, expired, notYetValid, revoked }

class CertificateRejected implements Exception {
  const CertificateRejected(this.problem);
  final CertificateProblem problem;

  String get patientMessage => switch (problem) {
        CertificateProblem.malformed => 'This is not a LifeTrack doctor code.',
        CertificateProblem.untrustedRegistry || CertificateProblem.badSignature =>
          'This doctor could not be verified. Do not share your records.',
        CertificateProblem.expired => "This doctor's verification has expired. Ask them to renew it.",
        CertificateProblem.notYetValid => "This doctor's code is not valid yet.",
        CertificateProblem.revoked => "LifeTrack has withdrawn this doctor's verification. Do not share your records.",
      };

  @override
  String toString() => 'CertificateRejected(${problem.name})';
}

/// The registry public keys this app build trusts. Empty until the registry
/// exists — so every certificate is refused, which is the correct failure.
class RegistryTrust {
  const RegistryTrust(this.keys);
  const RegistryTrust.none() : keys = const [];

  final List<SimplePublicKey> keys;

  static const clockSkew = Duration(minutes: 5);

  Future<DoctorCertificate> verify(String qr, DateTime at) async {
    final cert = DoctorCertificate.decode(qr);
    if (keys.isEmpty) throw const CertificateRejected(CertificateProblem.untrustedRegistry);
    var ok = false;
    for (final k in keys) {
      if (await Ed25519().verify(cert.signedBytes, signature: Signature(cert.signature, publicKey: k))) {
        ok = true;
        break;
      }
    }
    if (!ok) throw const CertificateRejected(CertificateProblem.badSignature);
    // Phones and the registry disagree about the time by minutes; a
    // certificate issued moments ago must not look "not yet valid".
    if (at.add(clockSkew).isBefore(cert.issuedAt)) throw const CertificateRejected(CertificateProblem.notYetValid);
    if (!at.isBefore(cert.expiresAt)) throw const CertificateRejected(CertificateProblem.expired);
    return cert;
  }
}
