import '../ai/cloud_escalation.dart';
import '../ai/plane_a/reference_ranges.dart';
import '../ai/plane_c/cloud_gateway.dart';
import '../ai/plane_c/pseudonymised_slice.dart';
import '../audit/audit_log.dart';
import '../consent/consent_store.dart';
import '../consent/grants.dart';
import '../consent/record_access.dart';
import '../model/health_record.dart';
import '../storage/record_repository.dart';

/// The human side of a Plane C crossing, and the only file in `lib/` that
/// imports `plane_c` (`plane_boundary_test.dart` counts).
///
/// Lives outside `lib/src/ai/` because it does what no agent may: it issues a
/// grant. It does so only inside [confirm], i.e. at the patient's tap — the
/// grant is minted at the tap, not at setup, and it is Plane C's own.
class CloudEscalationAdapter implements CloudEscalation {
  CloudEscalationAdapter({
    required this.repository,
    required this.consent,
    required this.audit,
    required RecordAccess access,
    required this.policy,
    required CloudClient client,
    required this.clock,
    this.regionCode = 'IN',
  }) : _gateway = CloudGateway(access: access, audit: audit, policy: policy, client: client);

  /// Tier 2 as shipped: kill switch off, no network client (Phase 5).
  factory CloudEscalationAdapter.dark({
    required RecordRepository repository,
    required ConsentStore consent,
    required AuditLog audit,
    required RecordAccess access,
    required DateTime Function() clock,
  }) =>
      CloudEscalationAdapter(
        repository: repository,
        consent: consent,
        audit: audit,
        access: access,
        policy: const DisabledTierPolicy(),
        client: const UnavailableCloudClient(),
        clock: clock,
      );

  final RecordRepository repository;
  final ConsentStore consent;
  final AuditLog audit;
  final TierPolicy policy;
  final DateTime Function() clock;
  final String regionCode;
  final CloudGateway _gateway;

  @override
  bool isAvailable(DateTime at) => policy.tier2Enabled(regionCode, at);

  @override
  Disclosure prepare(String patientId, DateTime at) {
    final patient = repository.patient(patientId)!;
    // The patient reading their own reports on their own phone to decide what
    // to send — no grant involved, nothing leaves here.
    final reports = [for (final r in repository.recordsOf(patientId)) if (r.dataClass == DataClass.reports) r];
    final slice = PseudonymisedSlice.fromRecords(patient: patient, records: reports, at: at);
    return Disclosure(
      patientId: patientId,
      payload: slice.canonical,
      lines: [
        'Age band ${slice.ageBand} · ${slice.sex}',
        for (final e in slice.entries)
          '${analyteName(e.analyte)} ${e.value} ${e.unit} · ${e.monthsAgo == 0 ? 'this month' : '${e.monthsAgo} months ago'}',
      ],
    );
  }

  @override
  Future<CloudOutcome> confirm(Disclosure disclosure, DateTime tappedAt) async {
    final grant = Grants.cloudOnce(patientId: disclosure.patientId, at: tappedAt);
    consent.issue(grant, at: tappedAt);
    await audit.append(AuditEntry(
      at: tappedAt,
      actorId: 'patient:${disclosure.patientId}',
      patientId: disclosure.patientId,
      action: AuditAction.grantIssued,
      dataClass: DataClass.reports,
      tokenId: grant.id,
      detail: 'one-time cloud analysis',
    ));
    final action = HumanAction(surface: 'cloud_consent', tappedAt: tappedAt, disclosure: disclosure.payload);
    try {
      final result = await _gateway.analyse(
        patient: repository.patient(disclosure.patientId)!,
        regionCode: regionCode,
        action: action,
        tokenId: grant.id,
        now: clock(),
      );
      return CloudOutcome(statements: result.statements);
    } on CloudRefused catch (e) {
      consent.revoke(grant.id);
      return CloudOutcome(statements: const [], refusal: e.message);
    } on ConsentDenied catch (e) {
      return CloudOutcome(statements: const [], refusal: 'Permission was refused (${e.reason.name}).');
    }
  }
}
