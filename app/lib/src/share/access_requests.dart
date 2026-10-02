import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../audit/audit_log.dart';
import '../consent/consent_token.dart';
import '../storage/sealed_store.dart';
import 'relay.dart';

/// A verified doctor's request, waiting for the patient.
class PendingRequest {
  const PendingRequest({required this.patientId, required this.request, required this.doctor, required this.receivedAt});
  final String patientId;
  final AccessRequest request;
  final DoctorCertificate doctor;
  final DateTime receivedAt;

  Set<AccessLevel> get levels => {
        for (final l in request.levels) ?AccessLevel.values.where((v) => v.name == l).firstOrNull,
      };
}

/// Requests that arrive by LifeTrack ID. Each is verified on arrival —
/// registry certificate and signature (CLAUDE.md #15) — and nothing is
/// shared until the patient approves on this phone.
class AccessRequestInbox {
  AccessRequestInbox({required this.sealed, required this.audit, required this.relay, required this.trust, this.doctors = const UnknownDoctorStatus()});

  static const _blob = 'access_requests';

  final SealedStore sealed;
  final AuditLog audit;
  final RelayClient relay;
  final RegistryTrust trust;

  /// A doctor revoked since their certificate was issued is refused online.
  final DoctorStatus doctors;

  Future<List<Map<String, Object?>>> _all() async => [for (final e in (await sealed.read(_blob) as List?) ?? const []) (e as Map).cast()];

  /// Unexpired requests for [patientId], newest first.
  Future<List<PendingRequest>> pending(String patientId, DateTime at) async {
    final out = <PendingRequest>[];
    for (final e in await _all()) {
      if (e['patientId'] != patientId) continue;
      final r = AccessRequest.fromJson((e['request']! as Map).cast());
      if (!at.isBefore(r.expiresAt)) continue;
      try {
        out.add(PendingRequest(patientId: patientId, request: r, doctor: await r.verify(trust, at), receivedAt: DateTime.parse(e['at']! as String)));
      } on Object {
        // A certificate that lapsed since arrival is no longer shown.
      }
    }
    out.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return out;
  }

  /// Inbox handler for `access_request` messages to [patientId]'s mailbox.
  Future<void> Function(Map<String, Object?>) handler({required String patientId, required String? lifeTrackId, required DateTime at}) => (p) async {
        final r = AccessRequest.fromJson(p);
        if (lifeTrackId == null || r.lifeTrackId != lifeTrackId) throw StateError('a request for a different LifeTrack ID');
        if (!at.isBefore(r.expiresAt) || r.expiresAt.difference(r.issuedAt) > AccessRequest.lifetime) throw StateError('an expired request');
        final DoctorCertificate d;
        try {
          d = await r.verify(trust, at);
        } on CertificateRejected catch (e) {
          throw StateError('a request from a doctor who could not be verified (${e.patientMessage})');
        }
        if (await doctors.stillApproved(d) == false) throw StateError('a request from a doctor whose verification LifeTrack has withdrawn');
        final all = await _all()..removeWhere((e) => (e['request']! as Map)['requestId'] == r.requestId);
        await sealed.write(_blob, [...all, {'patientId': patientId, 'request': r.toJson(), 'at': at.toIso8601String()}]);
        await audit.append(AuditEntry(
          at: at,
          actorId: Actors.doctor(d.registryId),
          patientId: patientId,
          action: AuditAction.accessRequested,
          detail: '${d.name} (${d.registrationNo}) asked for ${r.levels.join(', ')}',
        ));
      };

  Future<void> remove(String requestId) async {
    final all = await _all()..removeWhere((e) => (e['request']! as Map)['requestId'] == requestId);
    await sealed.write(_blob, all);
  }

  /// Tells the doctor's device, and logs it under Refused.
  Future<void> decline(PendingRequest p, {required String actorId, required DateTime at}) async {
    await remove(p.request.requestId);
    await audit.append(AuditEntry(
      at: at,
      actorId: actorId,
      patientId: p.patientId,
      action: AuditAction.denied,
      tokenId: 'grant-${p.patientId}-doctor-${p.doctor.registryId}-request',
      detail: 'You declined ${p.doctor.name}\'s request',
    ));
    final keyId = await RelayApi.keyId(p.doctor.encryptionKey);
    final exp = at.add(const Duration(hours: 47));
    final id = 'declined-${p.request.requestId}';
    await relay.deposit(
      mailbox: 'd-$keyId',
      grantId: id,
      envelope: await ShareEnvelope.seal(bundle: {'type': 'declined', 'requestId': p.request.requestId}, recipientKey: p.doctor.encryptionKey, keyId: keyId, grantId: id, expiresAt: exp),
      expiresAt: exp,
    );
  }
}
