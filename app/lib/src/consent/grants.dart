import 'dart:math';

import '../model/health_record.dart';
import 'consent_token.dart';

/// Factories for the grants the product issues. Every id is patient-scoped:
/// two patients granting the same doctor must never collide on one id.
///
/// These build tokens; only a human-driven flow passes them to
/// `ConsentStore.issue`.
abstract final class Grants {
  /// A doctor's consult grant. A fresh id per approval, so moving from
  /// Summary to All reports within one visit is a new grant, not a
  /// conflicting re-issue; "one live grant per doctor" is enforced by the
  /// share service superseding the old one.
  static ConsentToken clinician({
    required String patientId,
    required String doctorRegistryId,
    required Set<DataClass> scopes,
    required DateTime at,
    required Duration window,
    required GrantType type,
    String? grantorId,
    Set<AccessLevel> levels = const {},
    RecordFilter? filter,
    String? granteeKeyId,
  }) =>
      ConsentToken(
        id: 'grant-$patientId-doctor-$doctorRegistryId-${_nonce()}',
        patientId: patientId,
        grantedToActorId: Actors.doctor(doctorRegistryId),
        grantorId: grantorId ?? Actors.patient(patientId),
        purpose: GrantPurpose.clinicalConsult,
        scopes: scopes,
        issuedAt: at,
        expiresAt: at.add(window),
        type: type,
        levels: levels,
        filter: filter,
        granteeKeyId: granteeKeyId,
      );

  /// A visit: session-typed (a one-time grant would be spent by the first
  /// data class read), at most 4 hours, bound to one doctor device.
  static const visitWindow = Duration(hours: 4);

  static String _nonce() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Lets Plane A read reports and prescriptions to build on-device insights.
  /// Approved by the patient when they turn Insights on.
  static ConsentToken onDeviceInsights({required String patientId, required DateTime at}) =>
      ConsentToken(
        id: 'grant-agent-$patientId',
        patientId: patientId,
        grantedToActorId: Actors.planeA,
        grantorId: Actors.patient(patientId),
        purpose: GrantPurpose.onDeviceInsights,
        scopes: const {DataClass.reports, DataClass.prescriptions},
        issuedAt: at,
        expiresAt: at.add(const Duration(hours: 24)),
        type: GrantType.session,
      );

  /// Plane C's own grant: minted at the patient's tap, one-time, reports only,
  /// five minutes. Never the Plane A grant — spending another plane's
  /// authority would make the audit entry's lawful basis false.
  static ConsentToken cloudOnce({required String patientId, required DateTime at}) =>
      ConsentToken(
        id: 'grant-cloud-$patientId-${at.microsecondsSinceEpoch}',
        patientId: patientId,
        grantedToActorId: Actors.cloud,
        grantorId: Actors.patient(patientId),
        purpose: GrantPurpose.cloudAnalysis,
        scopes: const {DataClass.reports},
        issuedAt: at,
        expiresAt: at.add(const Duration(minutes: 5)),
        type: GrantType.oneTime,
      );
}
