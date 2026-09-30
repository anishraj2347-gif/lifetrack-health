import '../audit/audit_log.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../storage/record_repository.dart';
import 'consent_store.dart';
import 'consent_token.dart';

/// The only way anyone other than the patient reads records.
///
/// Authorize and audit are one sequence here, so no caller can obtain data
/// without leaving a trace (Mechanisms fig. 1). Refusals are audited too.
class RecordAccess {
  RecordAccess({required this.consent, required this.audit, required this.repository});

  final ConsentStore consent;
  final AuditLog audit;
  final RecordRepository repository;

  /// Allergies, conditions and family illnesses: the same authorize + audit
  /// sequence as [read], for the parts of the profile [dataClass] names.
  Future<ClinicalProfile> readProfile({
    required String tokenId,
    required String actorId,
    required String patientId,
    required DataClass dataClass,
    required GrantPurpose purpose,
    required DateTime at,
  }) async {
    assert(const {DataClass.allergies, DataClass.conditions, DataClass.familyHistory}.contains(dataClass));
    await _authorizeAndAudit(tokenId: tokenId, actorId: actorId, patientId: patientId, dataClass: dataClass, purpose: purpose, at: at);
    final p = repository.profileOf(patientId);
    return ClinicalProfile(
      allergies: dataClass == DataClass.allergies ? p.allergies : const [],
      conditions: dataClass == DataClass.conditions ? p.conditions : const [],
      familyIllnesses: dataClass == DataClass.familyHistory ? p.familyIllnesses : const [],
      updatedAt: p.updatedAt,
    );
  }

  Future<List<HealthRecord>> read({
    required String tokenId,
    required String actorId,
    required String patientId,
    required DataClass dataClass,
    required GrantPurpose purpose,
    required DateTime at,
  }) async {
    await _authorizeAndAudit(tokenId: tokenId, actorId: actorId, patientId: patientId, dataClass: dataClass, purpose: purpose, at: at);
    return [for (final r in repository.recordsOf(patientId)) if (r.dataClass == dataClass) r];
  }

  Future<ConsentToken> _authorizeAndAudit({
    required String tokenId,
    required String actorId,
    required String patientId,
    required DataClass dataClass,
    required GrantPurpose purpose,
    required DateTime at,
  }) async {
    final ConsentToken grant;
    try {
      grant = consent.authorize(
        tokenId: tokenId,
        actorId: actorId,
        patientId: patientId,
        dataClass: dataClass,
        purpose: purpose,
        at: at,
      );
    } on ConsentDenied catch (e) {
      await audit.append(AuditEntry(
        at: at,
        actorId: actorId,
        patientId: patientId,
        action: AuditAction.denied,
        dataClass: dataClass,
        tokenId: tokenId,
        detail: e.reason.name,
      ));
      rethrow;
    }
    await audit.append(AuditEntry(
      at: at,
      actorId: actorId,
      patientId: patientId,
      action: AuditAction.view,
      dataClass: dataClass,
      tokenId: grant.id,
      detail: grant.purpose.name,
    ));
    return grant;
  }
}
