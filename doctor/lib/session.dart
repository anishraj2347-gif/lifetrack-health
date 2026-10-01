import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'practice.dart';
import 'store/local_cipher.dart';

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

  Map<String, Object?> get patient => (bundle['patient'] as Map?)?.cast() ?? {};
  String get patientName => patient['name'] as String? ?? 'Patient';

  /// The same person across shares: their LifeTrack ID if sent, else the
  /// reply mailbox their phone keeps for them.
  String get patientKey =>
      (patient['lifeTrackId'] as String?) ?? ((bundle['replyTo'] as Map?)?['mailbox'] as String?) ?? 'name:$patientName';

  String get patientLine => [
        if (patient['sex'] == 'female') 'F' else if (patient['sex'] == 'male') 'M',
        if (patient['age'] != null) '${patient['age']} y',
      ].join(' · ');
  Duration remaining(DateTime now) => expiresAt.difference(now);
}

enum EnrolmentState { none, pending, approved, rejected, revoked }

/// This browser's doctor identity: two key pairs made here, never sent
/// anywhere except their public halves.
///
/// Everything kept in the browser — the key seeds, the inbox (still
/// encrypted to this device), the patient register, prescriptions and
/// consult notes — is sealed under a non-extractable WebCrypto key
/// ([LocalCipher]). Values written by older versions in the clear are
/// sealed the first time they are read.
class DoctorSession {
  DoctorSession._(this.prefs, this.base, this.cipher);

  static const _kEnc = 'lt.doctor.enc';
  static const _kSign = 'lt.doctor.sign';
  static const _kProfile = 'lt.doctor.profile';
  static const _kCert = 'lt.doctor.cert';
  static const _kInbox = 'lt.doctor.inbox';
  static const _kPatients = 'lt.doctor.patients';
  static const _kRx = 'lt.doctor.prescriptions';
  static const _kNotes = 'lt.doctor.notes';
  static const _kTheme = 'lt.doctor.theme';

  final SharedPreferences prefs;
  final Uri base;
  final LocalCipher cipher;

  Future<String?> _get(String k) async {
    final v = prefs.getString(k);
    if (v == null) return null;
    if (!v.startsWith(LocalCipher.prefix)) {
      await _set(k, v); // plain, from before 1.3.0: seal it now
      return v;
    }
    try {
      return await cipher.open(v);
    } on Object {
      return null; // sealed under a key this browser no longer has
    }
  }

  Future<void> _set(String k, String v) async => prefs.setString(k, await cipher.seal(v));

  /// 'system' (follow the device), 'light' or 'dark'.
  String themeChoice = 'system';

  Future<void> setThemeChoice(String choice) async {
    themeChoice = choice;
    await _set(_kTheme, choice);
  }

  /// Patients who have shared with this doctor, most recent first.
  final List<PatientEntry> patients = [];

  /// Prescriptions this doctor signed, newest first.
  final List<RxEntry> prescriptions = [];

  /// Private consult notes, newest first.
  final List<ConsultNote> notes = [];

  PatientEntry? patientByKey(String key) => patients.where((p) => p.key == key).firstOrNull;
  ReceivedShare? openShareFor(String key) => inbox.where((s) => s.patientKey == key).firstOrNull;
  List<RxEntry> prescriptionsFor(String key) => [for (final r in prescriptions) if (r.patientKey == key) r];
  List<ConsultNote> notesFor(String key) => [for (final n in notes) if (n.patientKey == key) n];

  Future<void> _savePractice() async {
    await _set(_kPatients, jsonEncode([for (final p in patients) p.toJson()]));
    await _set(_kRx, jsonEncode([for (final r in prescriptions) r.toJson()]));
    await _set(_kNotes, jsonEncode([for (final n in notes) n.toJson()]));
  }

  Future<void> _loadPractice() async {
    List<Map<String, Object?>> list(String? raw) => [for (final m in (jsonDecode(raw ?? '[]') as List)) (m as Map).cast()];
    patients
      ..clear()
      ..addAll(list(await _get(_kPatients)).map(PatientEntry.fromJson));
    prescriptions
      ..clear()
      ..addAll(list(await _get(_kRx)).map(RxEntry.fromJson));
    notes
      ..clear()
      ..addAll(list(await _get(_kNotes)).map(ConsultNote.fromJson));
  }

  /// Adds the patient behind [sh] to the register, or updates them.
  void registerShare(ReceivedShare sh) {
    final p = patientByKey(sh.patientKey);
    final levels = [for (final l in (sh.bundle['levels'] as List?) ?? []) '$l'];
    if (p == null) {
      patients.add(PatientEntry(
        key: sh.patientKey,
        name: sh.patientName,
        sex: sh.patient['sex'] as String?,
        age: sh.patient['age'] as int?,
        lifeTrackId: sh.patient['lifeTrackId'] as String?,
        firstSeen: sh.receivedAt,
        lastShared: sh.receivedAt,
        levels: levels,
      ));
    } else {
      p
        ..name = sh.patientName
        ..sex = sh.patient['sex'] as String? ?? p.sex
        ..age = sh.patient['age'] as int? ?? p.age
        ..lifeTrackId = sh.patient['lifeTrackId'] as String? ?? p.lifeTrackId
        ..lastShared = sh.receivedAt
        ..shares += 1
        ..levels = levels;
    }
    patients.sort((a, b) => b.lastShared.compareTo(a.lastShared));
  }

  /// Adds or replaces (same id) a private consult note.
  Future<void> saveNote(ConsultNote n) async {
    for (final f in [n.complaint, n.findings, n.advice]) {
      if (f.length > ConsultNote.maxField) throw ArgumentError('Keep each part under ${ConsultNote.maxField} characters.');
    }
    notes
      ..removeWhere((x) => x.id == n.id)
      ..add(n)
      ..sort((a, b) => b.at.compareTo(a.at));
    await _savePractice();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((x) => x.id == id);
    await _savePractice();
  }

  static String newNoteId() => 'note-${DateTime.now().microsecondsSinceEpoch}';
  final http.Client _http = http.Client();

  SimpleKeyPair? enc;
  SimpleKeyPair? sign;
  Map<String, String> profile = {};
  String? certificateQr;
  EnrolmentState state = EnrolmentState.none;
  String? note;
  final List<ReceivedShare> inbox = [];

  /// Requests this doctor sent by LifeTrack ID, newest first.
  final List<SentRequest> sent = [];

  /// Asks a patient, by their 12-digit LifeTrack ID, for access at [levels].
  /// Signed with this device's key and sealed to the patient's phone; the
  /// patient approves, lowers or declines there.
  Future<void> requestAccess({required String lifeTrackId, required List<String> levels, String? note}) async {
    final id = LifeTrackId.parse(lifeTrackId) ?? (throw Exception('That is not a valid LifeTrack ID — check the 12 digits.'));
    final look = await _http.get(base.resolve('/v1/ids/$id'));
    if (look.statusCode == 404) throw Exception('No patient has that LifeTrack ID.');
    if (look.statusCode != 200) throw Exception('LifeTrack could not be reached (${look.statusCode}).');
    final j = jsonDecode(look.body) as Map;
    final key = base64Decode(j['key']! as String);
    final now = DateTime.now();
    final r = await AccessRequest(
      requestId: 'req-${now.microsecondsSinceEpoch}',
      lifeTrackId: id,
      levels: levels,
      issuedAt: now,
      expiresAt: now.add(AccessRequest.lifetime - const Duration(minutes: 5)),
      certificate: certificateQr!,
      note: note == null || note.trim().isEmpty ? null : note.trim(),
    ).signedWith(sign!);
    final sealed = await ShareEnvelope.seal(bundle: r.toJson(), recipientKey: key, keyId: await RelayApi.keyId(key), grantId: r.requestId, expiresAt: r.expiresAt);
    final put = await _http.put(
      base.resolve(RelayApi.itemPath(j['mailbox']! as String, r.requestId)),
      body: sealed,
      headers: {RelayApi.hExpires: r.expiresAt.toUtc().toIso8601String(), 'content-type': 'application/octet-stream'},
    );
    if (put.statusCode != 201) throw Exception('Request not delivered (${put.statusCode}).');
    sent.insert(0, SentRequest(requestId: r.requestId, lifeTrackId: id, levels: levels, at: now));
  }

  /// Names whose shares the patient closed since the screen last showed it.
  final List<String> closedByPatient = [];

  static Future<DoctorSession> load(Uri base, {LocalCipher? cipher}) async {
    final s = DoctorSession._(await SharedPreferences.getInstance(), base, cipher ?? platformCipher());
    s.themeChoice = await s._get(_kTheme) ?? 'system';
    final encSeed = await s._get(_kEnc);
    final signSeed = await s._get(_kSign);
    if (encSeed != null && signSeed != null) {
      s.enc = await X25519().newKeyPairFromSeed(base64Decode(encSeed));
      s.sign = await Ed25519().newKeyPairFromSeed(base64Decode(signSeed));
      s.profile = (jsonDecode(await s._get(_kProfile) ?? '{}') as Map).cast();
      s.certificateQr = await s._get(_kCert);
      s.state = s.certificateQr != null ? EnrolmentState.approved : EnrolmentState.pending;
      await s._loadPractice();
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
    await _set(_kEnc, base64Encode(await e.extractPrivateKeyBytes()));
    await _set(_kSign, base64Encode(await s.extractPrivateKeyBytes()));
    await _set(_kProfile, jsonEncode(profile));
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
      if (certificateQr != null) await _set(_kCert, certificateQr!);
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
    for (final i in ((jsonDecode(r.body) as Map)['items'] as List?) ?? []) {
      final env = base64Decode((i as Map)['envelope']! as String);
      final header = (jsonDecode(utf8.decode(env)) as Map);
      try {
        final bundle = await ShareEnvelope.open(Uint8List.fromList(env), enc!, now);
        if (bundle['type'] == 'declined') {
          for (final r in sent) {
            if (r.requestId == bundle['requestId']) r.declined = true;
          }
          continue;
        }
        if (bundle['type'] == 'close') {
          // The patient ended access. Only their phone knows this secret.
          final gone = inbox.where((s) => s.grantId == bundle['grantId'] && s.bundle['closeSecret'] == bundle['closeSecret']).toList();
          for (final s in gone) {
            inbox.remove(s);
            closedByPatient.add(s.patientName);
          }
          continue;
        }
        final grantId = i['grantId']! as String;
        final share = ReceivedShare(grantId: grantId, bundle: bundle, expiresAt: DateTime.parse(header['exp']! as String), receivedAt: now);
        inbox.removeWhere((s) => s.patientKey == share.patientKey);
        inbox.insert(0, share);
        registerShare(share);
        _sealed[grantId] = (i['envelope']! as String, now);
        n++;
      } on ShareExpired {
        // Arrived too late: dropped unread.
      }
    }
    await _saveInbox();
    if (n > 0) await _savePractice();
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
    await _set(_kInbox, jsonEncode([
      for (final e in _sealed.entries) {'grantId': e.key, 'envelope': e.value.$1, 'at': e.value.$2.toIso8601String()},
    ]));
  }

  Future<void> _restoreInbox() async {
    final now = DateTime.now();
    for (final i in (jsonDecode(await _get(_kInbox) ?? '[]') as List).cast<Map>()) {
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
    final exp = DateTime.now().add(Duration(hours: 47));
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
    prescriptions.insert(0, RxEntry(patientKey: share.patientKey, patientName: share.patientName, patientLine: share.patientLine, rx: rx));
    await _savePractice();
    return rx;
  }

  Future<void> forget() async {
    await prefs.clear();
    await cipher.reset();
    patients.clear();
    prescriptions.clear();
    notes.clear();
    enc = null;
    sign = null;
    certificateQr = null;
    state = EnrolmentState.none;
    inbox.clear();
  }
}

class SentRequest {
  SentRequest({required this.requestId, required this.lifeTrackId, required this.levels, required this.at});
  final String requestId;
  final String lifeTrackId;
  final List<String> levels;
  final DateTime at;
  bool declined = false;
}
