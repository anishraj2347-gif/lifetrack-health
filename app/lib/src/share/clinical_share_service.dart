import 'dart:convert';
import 'dart:typed_data';

import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../audit/audit_log.dart';
import '../consent/consent_store.dart';
import '../consent/consent_token.dart';
import '../consent/grants.dart';
import '../consent/record_access.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../storage/record_repository.dart';
import 'http_relay_client.dart' show WithdrawTokenStore, InMemoryWithdrawTokens;
import 'pending_closes.dart';
import 'relay.dart';
import 'reply_identity.dart';
import 'share_bundle.dart';

class ShareReceipt {
  const ShareReceipt({required this.grant, required this.doctor, required this.withheld});
  final ConsentToken grant;
  final DoctorCertificate doctor;
  final Set<DataClass> withheld;
}

class PrescriptionRejected implements MessageRefused {
  const PrescriptionRejected(this.reason);
  @override
  final String reason;
  @override
  String toString() => 'PrescriptionRejected: $reason';
}

/// Phase 2's clinical share (CLAUDE.md #1a–1d). Runs on the patient's phone.
///
/// Every public method is a human act: the patient scanned a doctor's code
/// and tapped Share, or tapped End access. Nothing here is callable from
/// `lib/src/ai/` (plane_boundary_test.dart).
class ClinicalShareService {
  ClinicalShareService({
    required this.trust,
    required this.consent,
    required this.access,
    required this.audit,
    required this.repository,
    required this.relay,
    required this.replyIdentity,
    this.originals,
    this.shrink,
    this.lifeTrackIdOf,
    this.doctors = const UnknownDoctorStatus(),
    WithdrawTokenStore? keyBook,
    PendingCloseStore? closes,
  })  : keyBook = keyBook ?? InMemoryWithdrawTokens(),
        closes = closes ?? InMemoryPendingCloses();

  /// Asked before anything goes to a doctor or is taken from one: a doctor
  /// revoked since their certificate was issued is refused while online.
  final DoctorStatus doctors;

  Future<void> _stillApproved(DoctorCertificate cert) async {
    if (await doctors.stillApproved(cert) == false) throw const CertificateRejected(CertificateProblem.revoked);
  }

  /// The patient's LifeTrack ID, sent with a share so the doctor can ask for
  /// access again later (#17a); the patient still approves every request.
  final String? Function(String patientId)? lifeTrackIdOf;

  /// Each live share's doctor key, so ending access can tell that device to
  /// close a share it has already picked up.
  final WithdrawTokenStore keyBook;

  /// Doctors' devices still to be told that access ended (see [endAccess]).
  final PendingCloseStore closes;

  /// The queue, loaded once: every change goes through this one list.
  late final Future<List<PendingClose>> _queue = closes.load();

  /// Loads a record's original pages; null in tests that do not need them.
  final Future<List<Uint8List>> Function(HealthRecord record)? originals;

  /// Budget for original pages in one share (raw JPEG bytes). The relay
  /// takes 5 MB per share; base64 grows bytes by a third.
  static const originalsBudget = 2800 * 1024;

  /// Makes a smaller copy of a page for a share; pages go as stored when null.
  final Uint8List Function(Uint8List page)? shrink;


  final RegistryTrust trust;
  final ConsentStore consent;
  final RecordAccess access;
  final AuditLog audit;
  final RecordRepository repository;
  final RelayClient relay;

  /// This phone's reply mailbox and key, per patient.
  final Future<ReplyIdentity> Function(String patientId) replyIdentity;

  /// Step 1 — the patient scans the doctor's code. Throws
  /// [CertificateRejected] with a patient-readable reason.
  Future<DoctorCertificate> scan(String qr, DateTime at) async {
    final cert = await trust.verify(qr, at);
    await _stillApproved(cert);
    return cert;
  }

  /// Step 2 — the patient approves [levels] (optionally narrowed by
  /// [filter]) for this doctor. [requested] is what the doctor asked for, so
  /// the doctor can be told what was withheld.
  Future<ShareReceipt> share({
    required String patientId,
    required DoctorCertificate doctor,
    required Set<AccessLevel> levels,
    required DateTime at,
    RecordFilter? filter,
    Set<AccessLevel>? requested,
    Duration window = Grants.visitWindow,
    String? grantorId,
    String? sharedBy,
  }) async {
    if (levels.isEmpty) throw ArgumentError('Pick at least one level.');
    if (!at.isBefore(doctor.expiresAt)) throw const CertificateRejected(CertificateProblem.expired);
    await _stillApproved(doctor);
    final patient = repository.patient(patientId)!;
    final keyId = await doctor.keyId();
    final mailbox = await RelayApi.doctorMailbox(doctor.encryptionKey);
    final actor = Actors.doctor(doctor.registryId);

    // One live grant per doctor per patient: a new approval replaces the old,
    // but only once it has gone. If the server is off, what the doctor has
    // now stays as it is, rather than ending with nothing in its place.
    final replacing = [for (final g in consent.activeGrantsFor(patientId, at)) if (g.grantedToActorId == actor) g];

    final scopes = scopesFor(levels);
    final grant = Grants.clinician(
      patientId: patientId,
      doctorRegistryId: doctor.registryId,
      scopes: scopes,
      at: at,
      window: window,
      type: GrantType.session,
      levels: levels,
      filter: filter,
      granteeKeyId: keyId,
      grantorId: grantorId,
    );
    consent.issue(grant, at: at);
    await audit.append(AuditEntry(
      at: at,
      actorId: grant.grantorId,
      patientId: patientId,
      action: AuditAction.grantIssued,
      tokenId: grant.id,
      detail: '${doctor.name} (${doctor.registrationNo}) · ${levels.map((l) => l.name).join(', ')} · ${window.inHours} h',
    ));

    // Every part of the bundle is released through RecordAccess: authorized
    // against the stored grant and audited, like any other read.
    Future<List<HealthRecord>> read(DataClass c) async => scopes.contains(c)
        ? access.read(tokenId: grant.id, actorId: actor, patientId: patientId, dataClass: c, purpose: GrantPurpose.clinicalConsult, at: at)
        : const [];
    Future<ClinicalProfile> profile(DataClass c) async => scopes.contains(c)
        ? access.readProfile(tokenId: grant.id, actorId: actor, patientId: patientId, dataClass: c, purpose: GrantPurpose.clinicalConsult, at: at)
        : const ClinicalProfile();

    final allergies = await profile(DataClass.allergies);
    final conditions = await profile(DataClass.conditions);
    final family = await profile(DataClass.familyHistory);
    final requestedScopes = scopesFor(requested ?? levels);
    final released = {
      for (final r in [...await read(DataClass.reports), ...await read(DataClass.prescriptions), ...await read(DataClass.scans)]) r.id: r,
    };
    final bundle = ShareBundle.build(
      patient: patient,
      at: at,
      levels: levels,
      filter: filter,
      requested: requestedScopes,
      granted: scopes,
      allergies: allergies.allergies,
      noKnownAllergies: allergies.noneKnown,
      conditions: conditions.conditions,
      familyIllnesses: family.familyIllnesses,
      prescriptions: [for (final r in released.values) if (r.kind == RecordKind.prescription) r],
      reports: [for (final r in released.values) if (r.kind == RecordKind.report) r],
      scans: [for (final r in released.values) if (r.kind == RecordKind.scan) r],
      homeReadings: scopes.contains(DataClass.vitals)
          ? await access.readVitals(
              tokenId: grant.id, actorId: actor, patientId: patientId, purpose: GrantPurpose.clinicalConsult, at: at, from: at.subtract(const Duration(days: 30)))
          : const [],
      profileUpdatedAt: repository.profileOf(patientId).updatedAt,
    );
    final reply = await replyIdentity(patientId);
    bundle
      ..['replyTo'] = reply.replyTo
      ..['sharedBy'] = sharedBy
      ..['closeSecret'] = await _closeSecret(patientId, grant.id);
    if (lifeTrackIdOf?.call(patientId) case final id?) {
      bundle['patient'] = {...(bundle['patient']! as Map).cast<String, Object?>(), 'lifeTrackId': id};
      // Proves this phone holds the reply key the ID is registered to; the
      // registry lookup alone is public and proves nothing (doctor app).
      bundle['senderProof'] = await SenderProof.make(replyKeyPair: reply.keyPair, doctorKey: doctor.encryptionKey, grantId: grant.id, lifeTrackId: id);
    }
    await _attachOriginals(bundle, released);

    final envelope = await ShareEnvelope.seal(
      bundle: bundle,
      recipientKey: doctor.encryptionKey,
      keyId: keyId,
      grantId: grant.id,
      expiresAt: grant.expiresAt,
    );
    // Audited before it leaves: a failed send is still recorded (#1c, #13).
    await audit.append(AuditEntry(
      at: at,
      actorId: grant.grantorId,
      patientId: patientId,
      action: AuditAction.clinicalShare,
      tokenId: grant.id,
      detail: 'Sent to ${doctor.name} (${doctor.registrationNo}), encrypted to their device',
    ));
    await keyBook.put('dk-${grant.id}', base64Encode(doctor.encryptionKey));
    try {
      await relay.deposit(mailbox: mailbox, grantId: grant.id, envelope: envelope, expiresAt: grant.expiresAt);
    } on Object {
      // A timed-out send may still have landed, so this goes through the same
      // withdrawal and close as any other ending.
      await _end(grant, at, 'share not delivered');
      rethrow;
    }
    for (final g in replacing) {
      await _end(g, at, 'replaced by a new approval', replaced: true);
    }
    // Kept so the patient can change how long this share lasts without
    // scanning again; re-checked against the registry when used.
    await keyBook.put('dq-${grant.id}', doctor.encode());
    if (sharedBy != null) await keyBook.put('ds-${grant.id}', sharedBy);
    return ShareReceipt(grant: grant, doctor: doctor, withheld: requestedScopes.difference(scopes));
  }

  /// Adds the original pages of the records this share already released —
  /// the latest tests (Summary) and every document (All my reports) — until
  /// the budget is used. What does not fit is counted, so the doctor knows
  /// to ask to see it on the patient's phone.
  Future<void> _attachOriginals(Map<String, Object?> bundle, Map<String, HealthRecord> released) async {
    final load = originals;
    if (load == null) return;
    final wanted = <String>[
      for (final t in (bundle['latestTests'] as List?) ?? const []) (t as Map)['recordId']! as String,
      for (final d in (bundle['documents'] as List?) ?? const []) (d as Map)['id']! as String,
    ];
    final out = <String, List<String>>{};
    var used = 0, omitted = 0;
    for (final id in {...wanted}) {
      final r = released[id];
      if (r == null || r.attachmentId == null) continue;
      final pages = [for (final p in await load(r)) shrink?.call(p) ?? p];
      final size = pages.fold<int>(0, (a, p) => a + p.length);
      if (pages.isEmpty) continue;
      if (used + size > originalsBudget) {
        omitted++;
        continue;
      }
      used += size;
      out[id] = [for (final p in pages) base64Encode(p)];
    }
    bundle['originals'] = out;
    bundle['originalsOmitted'] = omitted;
  }

  Future<String> _closeSecret(String patientId, String grantId) async =>
      RelayApi.sha256Hex('${(await replyIdentity(patientId)).secret}|close|$grantId');

  /// Ending access works with no server: the grant ends on this phone at
  /// once and the log says so. Telling the relay and the doctor's device waits
  /// in a durable queue if it has to, and [retryPendingCloses] sends it.
  Future<EndAccessResult> endAccess(ConsentToken grant, DateTime at) => _end(grant, at, 'ended by patient');

  /// The patient changes how long a live share lasts — longer or shorter,
  /// never past 48 hours. The same levels and filter are sent again for the
  /// new [window] from [at], replacing the old share on the doctor's device;
  /// the doctor is checked against the registry again first.
  Future<ShareReceipt> changeTime(ConsentToken grant, Duration window, DateTime at) async {
    final qr = await keyBook.take('dq-${grant.id}');
    if (qr == null) throw StateError("To change the time, scan the doctor's code again.");
    final sharedBy = await keyBook.take('ds-${grant.id}');
    try {
      return await share(
        patientId: grant.patientId,
        doctor: await scan(qr, at),
        levels: grant.levels,
        filter: grant.filter,
        window: window,
        grantorId: grant.grantorId,
        sharedBy: sharedBy,
        at: at,
      );
    } on Object {
      await keyBook.put('dq-${grant.id}', qr);
      if (sharedBy != null) await keyBook.put('ds-${grant.id}', sharedBy);
      rethrow;
    }
  }

  /// Whether this share can have its time changed without a new scan.
  Future<bool> canChangeTime(ConsentToken grant) async {
    return await keyBook.peek('dq-${grant.id}') != null;
  }

  Future<EndAccessResult> _end(ConsentToken grant, DateTime at, String why, {bool replaced = false}) async {
    consent.revoke(grant.id);
    // Before anything leaves, so a failed send is still on record (#13).
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.patient(grant.patientId),
      patientId: grant.patientId,
      action: AuditAction.grantRevoked,
      tokenId: grant.id,
      detail: why,
    ));
    final keyId = grant.granteeKeyId;
    if (keyId == null) return EndAccessResult.doctorToldNow;
    final key = await keyBook.peek('dk-${grant.id}');
    final close = PendingClose(
      grantId: grant.id,
      patientId: grant.patientId,
      doctorActorId: grant.grantedToActorId,
      keyId: keyId,
      expiresAt: grant.expiresAt,
      doctorKey: key,
      closeSecret: key == null ? null : await _closeSecret(grant.patientId, grant.id),
      replaced: replaced,
    );
    // On disk before the first attempt: a restart mid-send still finishes it.
    final queue = await _queue;
    queue.add(close);
    await closes.save(queue);
    for (final k in ['dk-', 'dq-', 'ds-']) {
      await keyBook.take('$k${grant.id}');
    }
    try {
      await _deliver(close);
    } on Object {
      await _log(close, at, "ended on this phone; the server could not be reached, so the doctor's device has not been told yet");
      return EndAccessResult.waitingForServer;
    }
    await _settled(close);
    return EndAccessResult.doctorToldNow;
  }

  /// Removes anything not yet picked up; a share already delivered can only
  /// be discarded by the doctor app, which the screen says plainly. Safe to
  /// repeat: a second close for the same share finds nothing to close.
  Future<void> _deliver(PendingClose c) async {
    await relay.withdraw(mailbox: c.mailbox, grantId: c.grantId);
    final key = c.doctorKey;
    if (key == null) return;
    final id = 'close-${c.grantId}';
    await relay.deposit(
      mailbox: c.mailbox,
      grantId: id,
      envelope: await ShareEnvelope.seal(
        // Already picked up? This tells the doctor's device to close it now
        // rather than at expiry. Only this phone knows the secret, so nobody
        // else can close a patient's share. `replaced`: a new share with a new
        // time follows, so the doctor app does not announce that access ended.
        bundle: {'type': 'close', 'grantId': c.grantId, 'closeSecret': c.closeSecret, if (c.replaced) 'replaced': true},
        recipientKey: base64Decode(key),
        keyId: c.keyId,
        grantId: id,
        expiresAt: c.expiresAt,
      ),
      expiresAt: c.expiresAt,
    );
    await keyBook.take(id); // a close message is never pulled back
  }

  Future<void> _settled(PendingClose c) async {
    final queue = await _queue;
    queue.removeWhere((x) => x.grantId == c.grantId);
    await closes.save(queue);
  }

  /// Doctors' devices not yet told that [patientId]'s access ended.
  Future<List<PendingClose>> waitingToClose(String patientId) async => [
        for (final c in await _queue)
          if (c.patientId == patientId) c,
      ];

  Future<int>? _retrying;

  /// Sends what [endAccess] could not, and returns how many still wait. Runs
  /// one at a time. A message past its share's end time is dropped: the relay
  /// has deleted the share by then, and the doctor app closes it by itself.
  Future<int> retryPendingCloses(DateTime at) => _retrying ??= _retryCloses(at).whenComplete(() => _retrying = null);

  Future<int> _retryCloses(DateTime at) async {
    for (final c in [...await _queue]) {
      if (!at.isBefore(c.expiresAt)) {
        await _settled(c);
        await _log(c, at, "the share reached its end time before the doctor's device could be told");
        continue;
      }
      try {
        await _deliver(c);
      } on Object {
        continue;
      }
      await _settled(c);
      await _log(c, at, "doctor's device told that access ended");
    }
    return (await _queue).length;
  }

  Future<void> _log(PendingClose c, DateTime at, String detail) => audit.append(AuditEntry(
        at: at,
        actorId: Actors.patient(c.patientId),
        patientId: c.patientId,
        action: AuditAction.grantRevoked,
        tokenId: c.grantId,
        detail: detail,
      ));

/// A non-prescription message arriving in a reply mailbox (e.g. a family
  /// link). Returns a short line for the log, or throws to refuse it.
  /// Checks this patient's reply mailbox once and routes every message:
  /// prescriptions are verified and added; other kinds go to [handlers] by
  /// their `type`. Anything that cannot be opened or handled is refused and
  /// logged, never silently dropped. Returns (prescriptions added, handled
  /// other messages, refused).
  Future<(List<HealthRecord>, int, int)> collectInbox(
    String patientId,
    DateTime at, {
    Map<String, Future<void> Function(Map<String, Object?> payload)> handlers = const {},
  }) async {
    final me = await replyIdentity(patientId);
    final added = <HealthRecord>[];
    var handled = 0, refused = 0;
    for (final env in await relay.collect(mailbox: me.mailbox, secret: me.secret)) {
      try {
        final payload = await ShareEnvelope.open(env, me.keyPair, at);
        if (payload['prescription'] != null) {
          added.add(await acceptPrescription(
            patientId: patientId,
            rx: SignedPrescription.fromJson((payload['prescription']! as Map).cast()),
            doctorCertificateQr: payload['certificate']! as String,
            at: at,
          ));
        } else if (handlers[payload['type']] case final h?) {
          await h(payload);
          handled++;
        } else {
          throw const PrescriptionRejected('an unknown kind of message');
        }
      } on Object catch (e) {
        refused++;
        await audit.append(AuditEntry(
          at: at,
          actorId: 'relay',
          patientId: patientId,
          action: AuditAction.denied,
          detail: 'A message was refused: ${e is MessageRefused ? e.reason : e is CertificateRejected ? e.patientMessage : e is StateError ? e.message : 'it could not be opened'}',
        ));
      }
    }
    return (added, handled, refused);
  }

  /// Prescriptions only; kept for callers that have no other message kinds.
  Future<(List<HealthRecord>, int)> collectPrescriptions(String patientId, DateTime at) async {
    final (added, _, refused) = await collectInbox(patientId, at);
    return (added, refused);
  }

  /// A prescription arriving from a doctor. Accepted only when the doctor's
  /// certificate verifies (#15), the signature is by that certificate's key,
  /// it is for this patient, and the patient shared with this doctor within
  /// the last 48 hours.
  Future<HealthRecord> acceptPrescription({
    required String patientId,
    required SignedPrescription rx,
    required String doctorCertificateQr,
    required DateTime at,
  }) async {
    final cert = await trust.verify(doctorCertificateQr, at);
    await _stillApproved(cert);
    if (cert.registryId != rx.doctorRegistryId || cert.registrationNo != rx.registrationNo) {
      throw const PrescriptionRejected('The prescription and the doctor certificate do not match.');
    }
    if (!await rx.verifies(cert.signingKey)) throw const PrescriptionRejected('The signature does not verify.');
    if (rx.patientId != patientId) throw const PrescriptionRejected('This prescription is for someone else.');
    final keyId = await cert.keyId();
    final recentlyShared = consent.everIssuedTo(
      patientId: patientId,
      actorId: Actors.doctor(cert.registryId),
      granteeKeyId: keyId,
      since: at.subtract(kMaxGrantWindow),
    );
    if (!recentlyShared) throw const PrescriptionRejected('You have not shared with this doctor recently.');

    final record = HealthRecord(
      id: 'rx-${rx.doctorRegistryId}-${rx.issuedAt.microsecondsSinceEpoch}',
      patientId: patientId,
      kind: RecordKind.prescription,
      title: rx.medicine,
      date: rx.issuedAt,
      source: RecordSource.doctorIssued,
      doctor: '${rx.doctorName}, ${rx.qualification}',
      prescriberRegistration: rx.registrationNo,
      dose: Dose(morning: rx.morning, afternoon: rx.afternoon, night: rx.night),
      ingredient: rx.ingredient,
      endDate: rx.issuedAt.add(Duration(days: rx.days)),
      instructions: rx.note,
      timing: rx.timing,
    );
    await repository.add(record);
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.doctor(cert.registryId),
      patientId: patientId,
      action: AuditAction.prescriptionReceived,
      dataClass: DataClass.prescriptions,
      detail: '${rx.medicine} from ${rx.doctorName} (${rx.registrationNo})',
    ));
    return record;
  }
}
