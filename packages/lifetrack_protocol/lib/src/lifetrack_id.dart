import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'doctor_certificate.dart';

/// A person's LifeTrack ID: 12 digits, e.g. `1482 0937 5516`.
///
/// - Always starts with `1`. Aadhaar numbers never start with 0 or 1, so a
///   LifeTrack ID can never be mistaken for, or validate as, an Aadhaar number.
/// - The last digit is a Verhoeff check digit: any single wrong digit and any
///   swap of two neighbours is caught before anything is looked up.
/// - Random, not derived from a name, phone or Aadhaar. Unique because the
///   server registers it and refuses a duplicate.
abstract final class LifeTrackId {
  static const length = 12;

  static String generate([Random? rng]) {
    final r = rng ?? Random.secure();
    final body = '1${List.generate(10, (_) => r.nextInt(10)).join()}';
    return '$body${_checkDigit(body)}';
  }

  /// Digits only, or null if [input] is not a valid LifeTrack ID.
  static String? parse(String input) {
    final d = input.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^1\d{11}$').hasMatch(d)) return null;
    return _valid(d) ? d : null;
  }

  /// `1482 0937 5516` — grouped 4-4-4, as Aadhaar is printed.
  static String display(String id) => '${id.substring(0, 4)} ${id.substring(4, 8)} ${id.substring(8)}';

  /// `XXXX XXXX 5516` — the masked form, as masked Aadhaar is printed.
  static String masked(String id) => 'XXXX XXXX ${id.substring(8)}';

  // Verhoeff tables.
  static const _d = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7], [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3], [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
  ];
  static const _p = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7], [9, 4, 5, 3, 1, 2, 6, 8, 7, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
  ];
  static const _inv = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9];

  static int _checkDigit(String body) {
    var c = 0;
    final digits = body.split('').reversed.map(int.parse).toList();
    for (var i = 0; i < digits.length; i++) {
      c = _d[c][_p[(i + 1) % 8][digits[i]]];
    }
    return _inv[c];
  }

  static bool _valid(String id) {
    var c = 0;
    final digits = id.split('').reversed.map(int.parse).toList();
    for (var i = 0; i < digits.length; i++) {
      c = _d[c][_p[i % 8][digits[i]]];
    }
    return c == 0;
  }
}

/// A verified doctor asking a patient, by LifeTrack ID, for access at a
/// level. Signed with the doctor device's key; the patient's phone checks the
/// certificate and signature before showing it, and decides.
class AccessRequest {
  const AccessRequest({
    required this.requestId,
    required this.lifeTrackId,
    required this.levels,
    required this.issuedAt,
    required this.expiresAt,
    required this.certificate,
    this.note,
    this.accessHours,
    this.signature = const [],
  });

  static const lifetime = Duration(hours: 48);

  /// The choices a doctor can ask for, and a patient can give. Never more
  /// than 48 hours (CLAUDE.md #12).
  static const accessChoices = [1, 4, 12, 24, 48];

  final String requestId;
  final String lifeTrackId;

  /// `summary`, `allReports`, `familyIllnesses`.
  final List<String> levels;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// The doctor's registry certificate (QR form).
  final String certificate;

  /// Why, in the doctor's words. Optional.
  final String? note;

  /// How long the doctor asks to see the records, in hours (one of
  /// [accessChoices]). Null from doctor apps before 1.7.0: the patient's
  /// default applies. The patient may always give less.
  final int? accessHours;
  final List<int> signature;

  Map<String, Object?> _body() => {
        'v': 1,
        'type': 'access_request',
        'requestId': requestId,
        'lifeTrackId': lifeTrackId,
        'levels': levels,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'certificate': certificate,
        'note': note,
        // Only when set, so requests signed by older doctor apps still verify.
        if (accessHours != null) 'accessHours': accessHours,
      };

  List<int> get signedBytes => utf8.encode(jsonEncode(_body()));

  Future<AccessRequest> signedWith(SimpleKeyPair doctorSigningKey) async {
    final sig = await Ed25519().sign(signedBytes, keyPair: doctorSigningKey);
    return AccessRequest.fromJson({..._body(), 'signature': base64Encode(sig.bytes)});
  }

  /// The certificate must verify against [trust] and the signature against
  /// the key it names. Throws [CertificateRejected] or [StateError].
  Future<DoctorCertificate> verify(RegistryTrust trust, DateTime at) async {
    final cert = await trust.verify(certificate, at);
    final ok = await Ed25519().verify(signedBytes, signature: Signature(signature, publicKey: SimplePublicKey(cert.signingKey, type: KeyPairType.ed25519)));
    if (!ok) throw StateError('The request signature does not verify.');
    return cert;
  }

  Map<String, Object?> toJson() => {..._body(), 'signature': base64Encode(signature)};

  static AccessRequest fromJson(Map<String, Object?> j) => AccessRequest(
        requestId: j['requestId']! as String,
        lifeTrackId: j['lifeTrackId']! as String,
        levels: (j['levels']! as List).cast<String>(),
        issuedAt: DateTime.parse(j['issuedAt']! as String),
        expiresAt: DateTime.parse(j['expiresAt']! as String),
        certificate: j['certificate']! as String,
        note: j['note'] as String?,
        accessHours: accessChoices.contains(j['accessHours']) ? j['accessHours'] as int : null,
        signature: j['signature'] == null ? const [] : base64Decode(j['signature']! as String),
      );
}
