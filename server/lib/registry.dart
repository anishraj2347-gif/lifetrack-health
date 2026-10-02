import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

enum EnrolmentStatus { pending, approved, rejected, revoked }

class Enrolment {
  Enrolment({
    required this.registrationNo,
    required this.name,
    required this.speciality,
    required this.council,
    required this.encryptionKey,
    required this.signingKey,
    required this.requestedAt,
    this.status = EnrolmentStatus.pending,
    this.certificateQr,
    this.note,
  });

  final String registrationNo;
  final String name;
  final String speciality;
  final String council;
  final List<int> encryptionKey;
  final List<int> signingKey;
  final DateTime requestedAt;
  EnrolmentStatus status;
  String? certificateQr;
  String? note;

  Map<String, Object?> toJson() => {
        'reg': registrationNo,
        'name': name,
        'speciality': speciality,
        'council': council,
        'enc': base64Encode(encryptionKey),
        'sig': base64Encode(signingKey),
        'requestedAt': requestedAt.toIso8601String(),
        'status': status.name,
        'cert': certificateQr,
        'note': note,
      };

  static Enrolment fromJson(Map<String, Object?> j) => Enrolment(
        registrationNo: j['reg']! as String,
        name: j['name']! as String,
        speciality: j['speciality']! as String,
        council: j['council']! as String,
        encryptionKey: base64Decode(j['enc']! as String),
        signingKey: base64Decode(j['sig']! as String),
        requestedAt: DateTime.parse(j['requestedAt']! as String),
        status: EnrolmentStatus.values.byName(j['status']! as String),
        certificateQr: j['cert'] as String?,
        note: j['note'] as String?,
      );

  /// Short id of the encryption key (the doctor's mailbox). The doctor app
  /// shows the same fingerprint, so a reviewer can confirm with the doctor —
  /// by phone or in person — that the keys being approved are theirs.
  String get keyId => const DartSha256().hashSync(encryptionKey).bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Public view: never includes anything a patient shared.
  Map<String, Object?> publicJson() => {
        'registrationNo': registrationNo,
        'name': name,
        'speciality': speciality,
        'council': council,
        'status': status.name,
        'keyId': keyId,
        if (status == EnrolmentStatus.approved) 'certificate': certificateQr,
        'note': note,
      };
}

/// The doctor directory and certificate authority. Holds credentials only —
/// never patient data (blueprint §8.3).
///
/// Licence checks are MANUAL here: an admin approves each enrolment after
/// checking the National Medical Register / state council / HPR. No
/// automatic registry lookup exists yet, and the note on each enrolment says
/// so rather than implying one ran.
class DoctorRegistry {
  DoctorRegistry._(this._file, this._signingKey, this._enrolments);

  final File? _file;
  final SimpleKeyPair _signingKey;
  final Map<String, Enrolment> _enrolments;

  /// Short, so a revocation reaches every phone within a month even when a
  /// phone never asks the registry. The doctor app renews automatically.
  static const certificateLifetime = Duration(days: 30);

  /// A certificate this close to expiry is reissued when asked for.
  static const renewWithin = Duration(days: 10);

  static Future<DoctorRegistry> open({required SimpleKeyPair signingKey, File? file}) async {
    final map = <String, Enrolment>{};
    if (file != null && await file.exists()) {
      for (final e in (jsonDecode(await file.readAsString()) as List)) {
        final en = Enrolment.fromJson((e as Map).cast());
        map[en.registrationNo] = en;
      }
    }
    return DoctorRegistry._(file, signingKey, map);
  }

  Future<SimplePublicKey> publicKey() => _signingKey.extractPublicKey();

  Future<RegistryTrust> trust() async => RegistryTrust([await publicKey()]);

  Enrolment? byRegistration(String reg) => _enrolments[reg];

  List<Enrolment> withStatus(EnrolmentStatus s) => [for (final e in _enrolments.values) if (e.status == s) e];

  /// True unless [cert] belongs to the CURRENT approved enrolment with
  /// exactly these keys. Revocation is bound to the keys, so a later
  /// enrolment under the same registration number — by anyone — never brings
  /// an old certificate back.
  bool isRevoked(DoctorCertificate cert) {
    final e = _enrolments[cert.registryId];
    return e == null ||
        e.status != EnrolmentStatus.approved ||
        !_same(e.encryptionKey, cert.encryptionKey) ||
        !_same(e.signingKey, cert.signingKey);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The enrolment for [reg], its certificate reissued (same keys, new
  /// dates) when it is within [renewWithin] of expiring.
  Future<Enrolment?> current(String reg, DateTime at) async {
    final e = _enrolments[reg];
    if (e == null || e.status != EnrolmentStatus.approved || e.certificateQr == null) return e;
    if (DoctorCertificate.decode(e.certificateQr!).expiresAt.difference(at) > renewWithin) return e;
    e.certificateQr = await _issue(e, at);
    await _save();
    return e;
  }

  Future<Enrolment> enrol({
    required String registrationNo,
    required String name,
    required String speciality,
    required String council,
    required List<int> encryptionKey,
    required List<int> signingKey,
    required DateTime at,
  }) async {
    if (!RegExp(r'^[A-Z]{2,6}-[0-9]{3,10}$').hasMatch(registrationNo)) {
      throw ArgumentError('Registration number must look like DMC-12345.');
    }
    if (encryptionKey.length != 32 || signingKey.length != 32) throw ArgumentError('Keys must be 32 bytes.');
    final existing = _enrolments[registrationNo];
    if (existing != null && existing.status == EnrolmentStatus.approved) {
      throw StateError('Already approved. A new device needs the old certificate revoked first.');
    }
    // Keys waiting for review are never replaced: whoever enrolled second
    // could otherwise swap in their own keys just before an admin approves.
    if (existing != null && existing.status == EnrolmentStatus.pending) {
      throw StateError('An enrolment for $registrationNo is already waiting for review. If it is not yours, contact LifeTrack to have it rejected.');
    }
    final e = Enrolment(
      registrationNo: registrationNo,
      name: name,
      speciality: speciality,
      council: council,
      encryptionKey: encryptionKey,
      signingKey: signingKey,
      requestedAt: at,
      note: 'Awaiting manual licence check (no automatic registry lookup yet).',
    );
    _enrolments[registrationNo] = e;
    await _save();
    return e;
  }

  Future<Enrolment> approve(String reg, DateTime at, {String reviewer = 'admin'}) async {
    final e = _enrolments[reg] ?? (throw StateError('No enrolment for $reg.'));
    if (e.status != EnrolmentStatus.pending) throw StateError('$reg is ${e.status.name}.');
    e
      ..certificateQr = await _issue(e, at)
      ..status = EnrolmentStatus.approved
      ..note = 'Licence checked manually by $reviewer on ${at.toIso8601String().substring(0, 10)}.';
    await _save();
    return e;
  }

  Future<String> _issue(Enrolment e, DateTime at) async {
    DoctorCertificate cert(List<int> signature) => DoctorCertificate(
          registryId: e.registrationNo,
          name: e.name,
          speciality: e.speciality,
          council: e.council,
          registrationNo: e.registrationNo,
          encryptionKey: e.encryptionKey,
          signingKey: e.signingKey,
          issuedAt: at,
          expiresAt: at.add(certificateLifetime),
          signature: signature,
        );
    final sig = await Ed25519().sign(cert(const []).signedBytes, keyPair: _signingKey);
    return cert(sig.bytes).encode();
  }

  Future<void> reject(String reg, String reason) async {
    final e = _enrolments[reg] ?? (throw StateError('No enrolment for $reg.'));
    e
      ..status = EnrolmentStatus.rejected
      ..note = reason;
    await _save();
  }

  Future<void> revoke(String reg) async {
    final e = _enrolments[reg] ?? (throw StateError('No enrolment for $reg.'));
    e.status = EnrolmentStatus.revoked;
    await _save();
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in _enrolments.values) e.toJson()]), flush: true);
    await tmp.rename(f.path);
  }
}
