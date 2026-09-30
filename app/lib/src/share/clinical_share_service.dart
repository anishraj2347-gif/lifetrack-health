import '../audit/audit_log.dart';
import '../consent/consent_store.dart';
import '../consent/consent_token.dart';
import '../consent/grants.dart';
import '../consent/record_access.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../storage/record_repository.dart';
import 'doctor_certificate.dart';
import 'relay.dart';
import 'share_bundle.dart';
import 'share_envelope.dart';
import 'signed_prescription.dart';

class ShareReceipt {
  const ShareReceipt({required this.grant, required this.doctor, required this.withheld});
  final ConsentToken grant;
  final DoctorCertificate doctor;
  final Set<DataClass> withheld;
}

class PrescriptionRejected implements Exception {
  const PrescriptionRejected(this.reason);
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
  });

  final RegistryTrust trust;
  final ConsentStore consent;
  final RecordAccess access;
  final AuditLog audit;
  final RecordRepository repository;
  final RelayClient relay;

  /// Step 1 — the patient scans the doctor's code. Throws
  /// [CertificateRejected] with a patient-readable reason.
  Future<DoctorCertificate> scan(String qr, DateTime at) => trust.verify(qr, at);

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
  }) async {
    if (levels.isEmpty) throw ArgumentError('Pick at least one level.');
    if (!at.isBefore(doctor.expiresAt)) throw const CertificateRejected(CertificateProblem.expired);
    final patient = repository.patient(patientId)!;
    final keyId = await doctor.keyId();
    final actor = Actors.doctor(doctor.registryId);

    // One live grant per doctor per patient: a new approval replaces the old.
    for (final g in consent.activeGrantsFor(patientId, at)) {
      if (g.grantedToActorId == actor) await _end(g, at, 'replaced by a new approval');
    }

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
    );
    consent.issue(grant, at: at);
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.patient(patientId),
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
    final bundle = ShareBundle.build(
      patient: patient,
      at: at,
      levels: levels,
      filter: filter,
      requested: requestedScopes,
      granted: scopes,
      allergies: allergies.allergies,
      conditions: conditions.conditions,
      familyIllnesses: family.familyIllnesses,
      prescriptions: await read(DataClass.prescriptions),
      reports: await read(DataClass.reports),
      scans: await read(DataClass.scans),
      profileUpdatedAt: repository.profileOf(patientId).updatedAt,
    );

    final envelope = await ShareEnvelope.seal(
      bundle: bundle,
      doctorEncryptionKey: doctor.encryptionKey,
      keyId: keyId,
      grantId: grant.id,
      expiresAt: grant.expiresAt,
    );
    // Audited before it leaves: a failed send is still recorded (#1c, #13).
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.patient(patientId),
      patientId: patientId,
      action: AuditAction.clinicalShare,
      tokenId: grant.id,
      detail: 'Sent to ${doctor.name} (${doctor.registrationNo}), encrypted to their device',
    ));
    await relay.deposit(mailbox: keyId, grantId: grant.id, envelope: envelope, expiresAt: grant.expiresAt);
    return ShareReceipt(grant: grant, doctor: doctor, withheld: requestedScopes.difference(scopes));
  }

  /// The patient ends access. Removes anything not yet picked up; a share
  /// already delivered can only be discarded by the doctor app, which the
  /// screen says plainly.
  Future<void> endAccess(ConsentToken grant, DateTime at) => _end(grant, at, 'ended by patient');

  Future<void> _end(ConsentToken grant, DateTime at, String why) async {
    consent.revoke(grant.id);
    if (grant.granteeKeyId != null) {
      await relay.withdraw(mailbox: grant.granteeKeyId!, grantId: grant.id);
    }
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.patient(grant.patientId),
      patientId: grant.patientId,
      action: AuditAction.grantRevoked,
      tokenId: grant.id,
      detail: why,
    ));
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
      doctor: '${rx.doctorName}, ${rx.qualification} (${rx.registrationNo})',
      dose: Dose(morning: rx.morning, afternoon: rx.afternoon, night: rx.night),
      ingredient: rx.ingredient,
      endDate: rx.issuedAt.add(Duration(days: rx.days)),
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
