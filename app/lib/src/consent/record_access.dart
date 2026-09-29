import '../audit/audit_log.dart';
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

  Future<List<HealthRecord>> read({
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
    return [for (final r in repository.recordsOf(patientId)) if (r.dataClass == dataClass) r];
  }
}
