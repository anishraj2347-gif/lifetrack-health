import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'practice.dart';
import 'sample_data.dart';
import 'store/local_cipher.dart';

/// A patient's share as the doctor holds it: opened in memory; on disk only
/// as the envelope still encrypted to this device, dropped at the grant's
/// expiry or when the patient ends access. The doctor keeps their own consult note and any
/// prescription they write — not the patient's shared records.
class ReceivedShare {
  ReceivedShare({required this.grantId, required this.bundle, required this.expiresAt, required this.receivedAt, this.verified = false});
  final String grantId;
  final Map<String, Object?> bundle;
  final DateTime expiresAt;
  final DateTime receivedAt;

  /// True when the share proves it was sent by the holder of its reply key,
  /// and the LifeTrack ID in it is registered to that key — i.e. it came
  /// from that person's phone. Anyone can seal a "share" to this device's public key and write
  /// any name and ID into it; only a confirmed one is filed under that ID.
  final bool verified;

  Map<String, Object?> get patient => (bundle['patient'] as Map?)?.cast() ?? {};
  String get _name => patient['name'] as String? ?? 'Patient';
  String get patientName => verified ? _name : '$_name (identity not confirmed)';

  /// The LifeTrack ID, only when confirmed.
  String? get lifeTrackId => verified ? patient['lifeTrackId'] as String? : null;

  String get replyKey => ((bundle['replyTo'] as Map?)?['key'] as String?) ?? '';

  /// The same person across shares: their confirmed LifeTrack ID, else the
  /// key their phone receives replies with (which nobody else can use).
  String get patientKey => lifeTrackId ?? 'key:${keyTag(replyKey)}';

  static String keyTag(String key) =>
      const DartSha256().hashSync(utf8.encode(key)).bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
  DoctorSession._(this.prefs, this.base, this.cipher, [http.Client? client]) : _http = client ?? http.Client();

  static const _kEnc = 'lt.doctor.enc';
  static const _kSign = 'lt.doctor.sign';
  static const _kProfile = 'lt.doctor.profile';
  static const _kCert = 'lt.doctor.cert';
  static const _kRevoked = 'lt.doctor.revoked';
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
        lifeTrackId: sh.lifeTrackId,
        firstSeen: sh.receivedAt,
        lastShared: sh.receivedAt,
        levels: levels,
      ));
    } else {
      p
        ..name = sh.patientName
        ..sex = sh.patient['sex'] as String? ?? p.sex
        ..age = sh.patient['age'] as int? ?? p.age
        ..lifeTrackId = sh.lifeTrackId ?? p.lifeTrackId
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
  final http.Client _http;

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
  Future<void> requestAccess({required String lifeTrackId, required List<String> levels, String? note, int accessHours = 1}) async {
    if (!AccessRequest.accessChoices.contains(accessHours)) throw ArgumentError('Pick one of ${AccessRequest.accessChoices} hours.');
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
      accessHours: accessHours,
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

  static Future<DoctorSession> load(Uri base, {LocalCipher? cipher, http.Client? client}) async {
    final s = DoctorSession._(await SharedPreferences.getInstance(), base, cipher ?? platformCipher(), client);
    s.themeChoice = await s._get(_kTheme) ?? 'system';
    final encSeed = await s._get(_kEnc);
    final signSeed = await s._get(_kSign);
    if (encSeed != null && signSeed != null) {
      s.enc = await X25519().newKeyPairFromSeed(base64Decode(encSeed));
      s.sign = await Ed25519().newKeyPairFromSeed(base64Decode(signSeed));
      s.profile = (jsonDecode(await s._get(_kProfile) ?? '{}') as Map).cast();
      s.certificateQr = await s._get(_kCert);
      s.state = s.certificateQr != null ? EnrolmentState.approved : EnrolmentState.pending;
      // A revocation is remembered: a restart must not show this device as
      // approved again on the strength of an old certificate.
      if (await s._get(_kRevoked) case final why?) {
        s.state = EnrolmentState.revoked;
        s.note = why.isEmpty ? null : why;
      }
      await s._fingerprint();
      await s._loadPractice();
      await s._restoreInbox();
    }
    return s;
  }

  String get registrationNo => profile['registrationNo'] ?? '';

  /// This device's key fingerprint, as the registry shows it to the
  /// reviewer: `1a2b 3c4d 5e6f 7a8b`. The doctor reads it back when the
  /// reviewer calls, so nobody else's keys get approved in their name.
  String? keyFingerprint;

  Future<void> _fingerprint() async {
    final id = await RelayApi.keyId((await enc!.extractPublicKey()).bytes);
    keyFingerprint = [for (var i = 0; i < id.length; i += 4) id.substring(i, i + 4)].join(' ');
  }

  DateTime? _lastRenewCheck;

  /// Certificates last 30 days. Asks the registry for a renewed one when
  /// fewer than 10 days are left (at most hourly), and learns of a
  /// revocation the same way.
  Future<void> renewIfDue(DateTime now) async {
    final qr = certificateQr;
    if (qr == null) return;
    final last = _lastRenewCheck;
    if (last != null && now.difference(last) < const Duration(hours: 1)) return;
    DateTime? expires;
    try {
      expires = DoctorCertificate.decode(qr).expiresAt;
    } on Object {
      expires = null;
    }
    if (expires != null && expires.difference(now) > const Duration(days: 10)) return;
    _lastRenewCheck = now;
    await refreshStatus();
  }

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
    await _fingerprint();
  }

  /// Asks the registry whether the licence check is done.
  Future<void> refreshStatus() async {
    final r = await _http.get(base.resolve('/v1/doctors/$registrationNo'));
    if (r.statusCode != 200) return;
    final j = (jsonDecode(r.body) as Map).cast<String, Object?>();
    note = j['note'] as String?;
    final next = EnrolmentState.values.byName(j['status']! as String);
    final cert = j['certificate'] as String?;
    // The registry's approval is for one set of keys. If it now names other
    // keys, this device's certificate is no longer valid for this number.
    if (next == EnrolmentState.approved && cert != null) {
      final mine = (await enc!.extractPublicKey()).bytes;
      final theirs = DoctorCertificate.decode(cert).encryptionKey;
      if (base64Encode(mine) != base64Encode(theirs)) {
        await _revoked('Your registration number was approved for another device. Contact LifeTrack.');
        return;
      }
      certificateQr = cert;
      await _set(_kCert, cert);
      await prefs.remove(_kRevoked);
    }
    if (next == EnrolmentState.revoked) return _revoked(note);
    state = next;
  }

  /// Drops the certificate and remembers why, so the app stops picking up
  /// and stays "Not approved" across restarts.
  Future<void> _revoked(String? why) async {
    state = EnrolmentState.revoked;
    note = why;
    certificateQr = null;
    await prefs.remove(_kCert);
    await _set(_kRevoked, why ?? '');
  }

  Future<String> mailbox() async => RelayApi.doctorMailbox((await enc!.extractPublicKey()).bytes);

  /// Picks up every share waiting for this device; each is deleted from the
  /// relay as it is handed over. An item that cannot be opened is dropped on
  /// its own — it never costs the shares that came with it.
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
      try {
        if (await receive((i as Map)['envelope']! as String, now)) n++;
      } on Object {
        // Expired, damaged, or not sealed to this device: dropped unread.
      }
    }
    await _saveInbox();
    if (n > 0) await _savePractice();
    return n;
  }

  /// Opens one envelope (base64, as the relay hands it over). Returns true
  /// when it was a new share. Throws when it cannot be opened.
  Future<bool> receive(String raw, DateTime now) async {
    final env = Uint8List.fromList(base64Decode(raw));
    final header = (jsonDecode(utf8.decode(env)) as Map).cast<String, Object?>();
    final bundle = await ShareEnvelope.open(env, enc!, now);
    if (bundle['type'] == 'declined') {
      for (final r in sent) {
        if (r.requestId == bundle['requestId']) r.declined = true;
      }
      return false;
    }
    if (bundle['type'] == 'close') {
      // The patient ended access. Only their phone knows this secret.
      final gone = inbox.where((s) => s.grantId == bundle['grantId'] && s.bundle['closeSecret'] != null && s.bundle['closeSecret'] == bundle['closeSecret']).toList();
      for (final s in gone) {
        inbox.remove(s);
        // `replaced`: the patient changed the time; the new share follows.
        if (bundle['replaced'] != true) closedByPatient.add(s.patientName);
      }
      return false;
    }
    if (bundle['patient'] is! Map || bundle['replyTo'] is! Map) return false;
    // The grant id sealed into the envelope's header, not the relay's label.
    final grantId = header['gid']! as String;
    final share = ReceivedShare(
      grantId: grantId,
      bundle: bundle,
      expiresAt: DateTime.parse(header['exp']! as String),
      receivedAt: now,
      verified: await _confirmSender(bundle, grantId),
    );
    inbox.removeWhere((s) => s.patientKey == share.patientKey || s.grantId == grantId);
    inbox.insert(0, share);
    registerShare(share);
    _sealed[grantId] = (raw, now, share.verified);
    return true;
  }

  /// Whether the share came from the phone its LifeTrack ID belongs to. Two
  /// checks, both needed: the share proves its sender holds the reply key
  /// ([SenderProof] — the registry lookup is public, so anyone could copy a
  /// patient's ID and key into a share), and the registry has that ID on
  /// that key (only that person's phone can register or move it). Offline,
  /// unknown or unproven: not confirmed.
  Future<bool> _confirmSender(Map<String, Object?> bundle, String grantId) async {
    final id = LifeTrackId.parse('${(bundle['patient']! as Map)['lifeTrackId']}');
    final key = (bundle['replyTo']! as Map)['key'];
    final proof = bundle['senderProof'];
    if (id == null || key is! String || key.isEmpty || proof is! String) return false;
    try {
      final proven = await SenderProof.check(doctorKeyPair: enc!, replyKey: base64Decode(key), grantId: grantId, lifeTrackId: id, proof: proof);
      if (!proven) return false;
      final r = await _http.get(base.resolve('/v1/ids/$id'));
      if (r.statusCode != 200) return false;
      return (jsonDecode(r.body) as Map)['key'] == key;
    } on Object {
      return false;
    }
  }

  /// Demo builds only: fills the register with made-up patients (names end
  /// in "(sample)") — three with access open, three closed — plus
  /// prescriptions signed on this device and consult notes. Adding again
  /// replaces the samples, never anything real.
  Future<void> addSamplePatients(DateTime now, {bool allowed = demoTools}) async {
    if (!allowed) throw StateError('Sample patients are only in demo builds.');
    final people = samplePatients(now);
    final names = {for (final p in people) p.name};
    final keys = {for (final p in people) sampleId(p.name)};
    inbox.removeWhere((sh) => keys.contains(sh.patientKey));
    patients.removeWhere((p) => keys.contains(p.key));
    prescriptions.removeWhere((r) => names.contains(r.patientName));
    notes.removeWhere((n) => keys.contains(n.patientKey));

    final mine = (await enc!.extractPublicKey()).bytes;
    final keyId = await RelayApi.keyId(mine);
    for (final (i, p) in people.indexed) {
      final id = sampleId(p.name);
      final shared = now.subtract(Duration(days: p.sharedDaysAgo, minutes: 20 + i * 35));
      final entry = PatientEntry(
        key: id,
        name: p.name,
        sex: p.sex,
        age: p.age,
        lifeTrackId: id,
        firstSeen: shared.subtract(Duration(days: 30 * (p.shares - 1))),
        lastShared: shared,
        shares: p.shares,
        levels: [for (final l in (p.share?['levels'] as List?) ?? const ['summary']) '$l'],
      );
      patients.add(entry);
      final body = p.share;
      if (body == null) continue;
      // A reply key nobody holds: a prescription written to a sample goes
      // to the relay and expires unread.
      final reply = await (await X25519().newKeyPair()).extractPublicKey();
      final bundle = <String, Object?>{
        ...body,
        'patient': {'name': p.name, 'sex': p.sex, 'age': p.age, 'lifeTrackId': id},
        'patientRef': 'sample-$i',
        'replyTo': {'mailbox': 'p-${ReceivedShare.keyTag(base64Encode(reply.bytes))}${'0' * 48}', 'key': base64Encode(reply.bytes)},
        'closeSecret': RelayApi.newToken(),
      };
      final grantId = 'sample-$id';
      final expires = now.add(Duration(hours: 6 + i * 14));
      final env = await ShareEnvelope.seal(bundle: bundle, recipientKey: mine, keyId: keyId, grantId: grantId, expiresAt: expires);
      inbox.add(ReceivedShare(grantId: grantId, bundle: bundle, expiresAt: expires, receivedAt: shared, verified: true));
      _sealed[grantId] = (base64Encode(env), shared, true);
    }

    PatientEntry who(String name) => patients.firstWhere((p) => p.name == name);
    for (final r in sampleRx) {
      final p = who(r.patient);
      final rx = await SignedPrescription(
        patientId: 'sample',
        doctorRegistryId: registrationNo,
        doctorName: profile['name'] ?? 'Doctor',
        qualification: 'MBBS, MD',
        registrationNo: registrationNo,
        medicine: r.medicine,
        ingredient: r.ingredient,
        morning: r.dose[0],
        afternoon: r.dose[1],
        night: r.dose[2],
        days: r.days,
        issuedAt: now.subtract(Duration(days: r.daysAgo)).toUtc(),
        note: r.note,
        timing: r.timing,
      ).signedWith(sign!);
      prescriptions.add(RxEntry(patientKey: p.key, patientName: p.name, patientLine: p.sexAge, rx: rx));
    }
    for (final (i, n) in sampleNotes.indexed) {
      final at = now.subtract(Duration(days: n.daysAgo));
      notes.add(ConsultNote(
        id: 'note-sample-$i',
        patientKey: who(n.patient).key,
        at: at,
        complaint: n.complaint,
        findings: n.findings,
        advice: n.advice,
        followUp: n.followUpInDays == null ? null : DateTime(now.year, now.month, now.day).add(Duration(days: n.followUpInDays!)),
      ));
    }
    inbox.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    patients.sort((a, b) => b.lastShared.compareTo(a.lastShared));
    prescriptions.sort((a, b) => b.rx.issuedAt.compareTo(a.rx.issuedAt));
    notes.sort((a, b) => b.at.compareTo(a.at));
    await _saveInbox();
    await _savePractice();
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
  final Map<String, (String envelope, DateTime receivedAt, bool verified)> _sealed = {};

  Future<void> _saveInbox() async {
    _sealed.removeWhere((id, _) => !inbox.any((s) => s.grantId == id));
    await _set(_kInbox, jsonEncode([
      for (final e in _sealed.entries) {'grantId': e.key, 'envelope': e.value.$1, 'at': e.value.$2.toIso8601String(), 'verified': e.value.$3},
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
        final verified = i['verified'] == true;
        inbox.add(ReceivedShare(grantId: i['grantId']! as String, bundle: bundle, expiresAt: DateTime.parse(header['exp']! as String), receivedAt: at, verified: verified));
        _sealed[i['grantId']! as String] = (raw, at, verified);
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
