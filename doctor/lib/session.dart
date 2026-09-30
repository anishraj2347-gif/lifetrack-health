import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A patient's share as the doctor holds it: opened in memory; on disk only
/// as the envelope still encrypted to this device, dropped at the grant's
/// expiry or when the patient ends access. The doctor keeps their own consult note and any
/// prescription they write — not the patient's shared records.
class ReceivedShare {
  ReceivedShare({required this.grantId, required this.bundle, required this.expiresAt, required this.receivedAt});
  final String grantId;
  final Map<String, Object?> bundle;
  final DateTime expiresAt;
  final DateTime receivedAt;

  Map<String, Object?> get patient => (bundle['patient'] as Map?)?.cast() ?? const {};
  String get patientName => patient['name'] as String? ?? 'Patient';
  Duration remaining(DateTime now) => expiresAt.difference(now);
}

enum EnrolmentState { none, pending, approved, rejected, revoked }

/// This browser's doctor identity: two key pairs made here, never sent
/// anywhere except their public halves.
///
/// Demo-grade key storage: the seeds sit in the browser's local storage. A
/// real deployment keeps them in a non-extractable WebCrypto key or a
/// platform keystore (mobile app), and says so in its security notes.
class DoctorSession {
  DoctorSession._(this.prefs, this.base);

  static const _kEnc = 'lt.doctor.enc';
  static const _kSign = 'lt.doctor.sign';
  static const _kProfile = 'lt.doctor.profile';
  static const _kCert = 'lt.doctor.cert';
  static const _kInbox = 'lt.doctor.inbox';

  final SharedPreferences prefs;
  final Uri base;
  final http.Client _http = http.Client();

  SimpleKeyPair? enc;
  SimpleKeyPair? sign;
  Map<String, String> profile = {};
  String? certificateQr;
  EnrolmentState state = EnrolmentState.none;
  String? note;
  final List<ReceivedShare> inbox = [];

  /// Names whose shares the patient closed since the screen last showed it.
  final List<String> closedByPatient = [];

  static Future<DoctorSession> load(Uri base) async {
    final s = DoctorSession._(await SharedPreferences.getInstance(), base);
    final encSeed = s.prefs.getString(_kEnc);
    final signSeed = s.prefs.getString(_kSign);
    if (encSeed != null && signSeed != null) {
      s.enc = await X25519().newKeyPairFromSeed(base64Decode(encSeed));
      s.sign = await Ed25519().newKeyPairFromSeed(base64Decode(signSeed));
      s.profile = (jsonDecode(s.prefs.getString(_kProfile) ?? '{}') as Map).cast();
      s.certificateQr = s.prefs.getString(_kCert);
      s.state = s.certificateQr != null ? EnrolmentState.approved : EnrolmentState.pending;
      await s._restoreInbox();
    }
    return s;
  }

  String get registrationNo => profile['registrationNo'] ?? '';

  Future<void> enrol({required String name, required String speciality, required String council, required String registrationNo}) async {
    final e = await X25519().newKeyPair();
    final s = await Ed25519().newKeyPair();
    final r = await _http.post(
      base.resolve('/v1/doctors'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'speciality': speciality,
        'council': council,
        'registrationNo': registrationNo,
        'encryptionKey': base64Encode((await e.extractPublicKey()).bytes),
        'signingKey': base64Encode((await s.extractPublicKey()).bytes),
      }),
    );
    if (r.statusCode != 202) throw Exception((jsonDecode(r.body) as Map)['error'] ?? 'Enrolment failed (${r.statusCode}).');
    enc = e;
    sign = s;
    profile = {'name': name, 'speciality': speciality, 'council': council, 'registrationNo': registrationNo.toUpperCase()};
    await prefs.setString(_kEnc, base64Encode(await e.extractPrivateKeyBytes()));
    await prefs.setString(_kSign, base64Encode(await s.extractPrivateKeyBytes()));
    await prefs.setString(_kProfile, jsonEncode(profile));
    state = EnrolmentState.pending;
  }

  /// Asks the registry whether the licence check is done.
  Future<void> refreshStatus() async {
    final r = await _http.get(base.resolve('/v1/doctors/$registrationNo'));
    if (r.statusCode != 200) return;
    final j = (jsonDecode(r.body) as Map).cast<String, Object?>();
    note = j['note'] as String?;
    state = EnrolmentState.values.byName(j['status']! as String);
    if (state == EnrolmentState.approved) {
      certificateQr = j['certificate'] as String?;
      if (certificateQr != null) await prefs.setString(_kCert, certificateQr!);
    }
  }

  Future<String> mailbox() async => RelayApi.doctorMailbox((await enc!.extractPublicKey()).bytes);

  /// Picks up every share waiting for this device; each is deleted from the
  /// relay as it is handed over.
  Future<int> pickUp() async {
    final mb = await mailbox();
    final now = DateTime.now();
    final r = await _http.get(
      base.resolve(RelayApi.mailboxPath(mb)),
      headers: await RelayApi.doctorPickupHeaders(certificateQr: certificateQr!, signingKey: sign!, mailbox: mb, at: now),
    );
    if (r.statusCode != 200) throw Exception((jsonDecode(r.body) as Map)['error'] ?? 'Pickup failed (${r.statusCode}).');
    var n = 0;
    for (final i in ((jsonDecode(r.body) as Map)['items'] as List?) ?? const []) {
      final env = base64Decode((i as Map)['envelope']! as String);
      final header = (jsonDecode(utf8.decode(env)) as Map);
      try {
        final bundle = await ShareEnvelope.open(Uint8List.fromList(env), enc!, now);
        if (bundle['type'] == 'close') {
          // The patient ended access. Only their phone knows this secret.
          final gone = inbox.where((s) => s.grantId == bundle['grantId'] && s.bundle['closeSecret'] == bundle['closeSecret']).toList();
          for (final s in gone) {
            inbox.remove(s);
            closedByPatient.add(s.patientName);
          }
          continue;
        }
        inbox.removeWhere((s) => s.patientName == ((bundle['patient'] as Map?)?['name']));
        final grantId = i['grantId']! as String;
        inbox.insert(0, ReceivedShare(grantId: grantId, bundle: bundle, expiresAt: DateTime.parse(header['exp']! as String), receivedAt: now));
        _sealed[grantId] = (i['envelope']! as String, now);
        n++;
      } on ShareExpired {
        // Arrived too late: dropped unread.
      }
    }
    await _saveInbox();
    return n;
  }

  /// Drops every share whose access window has ended.
  Future<void> closeExpired(DateTime now) async {
    final before = inbox.length;
    inbox.removeWhere((s) => !now.isBefore(s.expiresAt));
    if (inbox.length != before) await _saveInbox();
  }

  /// Envelopes as they arrived — still encrypted to this device — so a page
  /// reload re-opens them instead of losing them. Each is removed when its
  /// share expires or the patient closes it.
  final Map<String, (String envelope, DateTime receivedAt)> _sealed = {};

  Future<void> _saveInbox() async {
    _sealed.removeWhere((id, _) => !inbox.any((s) => s.grantId == id));
    await prefs.setString(_kInbox, jsonEncode([
      for (final e in _sealed.entries) {'grantId': e.key, 'envelope': e.value.$1, 'at': e.value.$2.toIso8601String()},
    ]));
  }

  Future<void> _restoreInbox() async {
    final now = DateTime.now();
    for (final i in (jsonDecode(prefs.getString(_kInbox) ?? '[]') as List).cast<Map>()) {
      final raw = i['envelope']! as String;
      final env = base64Decode(raw);
      try {
        final bundle = await ShareEnvelope.open(Uint8List.fromList(env), enc!, now);
        final header = jsonDecode(utf8.decode(env)) as Map;
        final at = DateTime.parse(i['at']! as String);
        inbox.add(ReceivedShare(grantId: i['grantId']! as String, bundle: bundle, expiresAt: DateTime.parse(header['exp']! as String), receivedAt: at));
        _sealed[i['grantId']! as String] = (raw, at);
      } on Object {
        // Expired while the page was closed, or unreadable: dropped.
      }
    }
    inbox.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    await _saveInbox();
  }

  /// Signs a prescription with this device's key and seals it to the
  /// patient's reply key. Returns the doctor's own copy.
  Future<SignedPrescription> sendPrescription(ReceivedShare share, SignedPrescription draft) async {
    final rx = await draft.signedWith(sign!);
    final replyTo = (share.bundle['replyTo']! as Map).cast<String, Object?>();
    final key = base64Decode(replyTo['key']! as String);
    final exp = DateTime.now().add(const Duration(hours: 47));
    final sealed = await ShareEnvelope.seal(
      bundle: {'prescription': rx.toJson(), 'certificate': certificateQr},
      recipientKey: key,
      keyId: await RelayApi.keyId(key),
      grantId: 'rx-${share.grantId}-${rx.issuedAt.millisecondsSinceEpoch}',
      expiresAt: exp,
    );
    final r = await _http.put(
      base.resolve(RelayApi.itemPath(replyTo['mailbox']! as String, 'rx-${rx.issuedAt.millisecondsSinceEpoch}')),
      body: sealed,
      headers: {RelayApi.hExpires: exp.toUtc().toIso8601String(), 'content-type': 'application/octet-stream'},
    );
    if (r.statusCode != 201) throw Exception('Prescription not delivered (${r.statusCode}).');
    return rx;
  }

  Future<void> forget() async {
    await prefs.clear();
    enc = null;
    sign = null;
    certificateQr = null;
    state = EnrolmentState.none;
    inbox.clear();
  }
}
