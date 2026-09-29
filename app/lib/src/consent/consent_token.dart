import '../model/health_record.dart';

/// Why a grant exists. Part of the token's identity, not a label on it: a
/// grant for on-device insight building may not be spent on a cloud egress,
/// and the audit entry's stated lawful basis is read from here (CLAUDE.md #11).
enum GrantPurpose { clinicalConsult, onDeviceInsights, cloudAnalysis }

/// One-time grants are spent by their first successful authorization (walk-in
/// QR, Plane C tap). Session grants live until they expire or are revoked.
enum GrantType { oneTime, session }

/// Hard cap on any grant's window (blueprint §6.3; CLAUDE.md #12). Not
/// configurable — a longer window requires a fresh human approval.
const Duration kMaxGrantWindow = Duration(hours: 48);

/// Well-known actor ids. Agents are prefixed `agent:`; a doctor is
/// `doctor:<registry id>`.
abstract final class Actors {
  static const planeA = 'agent:plane_a';
  static const cloud = 'agent:cloud';
  static String doctor(String registryId) => 'doctor:$registryId';
  static String patient(String patientId) => 'patient:$patientId';
  static bool isAgent(String actorId) => actorId.startsWith('agent:');
}

class ConsentToken {
  ConsentToken({
    required this.id,
    required this.patientId,
    required this.grantedToActorId,
    required this.grantorId,
    required this.purpose,
    required Set<DataClass> scopes,
    required this.issuedAt,
    required this.expiresAt,
    required this.type,
  }) : scopes = Set.unmodifiable(scopes) {
    if (!expiresAt.isAfter(issuedAt)) {
      throw ArgumentError('A grant must expire after it is issued.');
    }
    if (expiresAt.difference(issuedAt) > kMaxGrantWindow) {
      throw ArgumentError('A grant may not exceed $kMaxGrantWindow.');
    }
    if (scopes.isEmpty) throw ArgumentError('A grant must name at least one data class.');
  }

  final String id;

  /// Whose data this grant opens.
  final String patientId;

  /// Who may exercise it. `authorize` enforces this against the caller.
  final String grantedToActorId;

  /// Who gave it. Equal to `patient:<patientId>` unless a guardian granted on
  /// behalf of a dependent (CLAUDE.md #14) — recorded so proxy consent is
  /// visible in the audit trail rather than indistinguishable from the patient's.
  final String grantorId;

  final GrantPurpose purpose;
  final Set<DataClass> scopes;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final GrantType type;

  bool isLiveAt(DateTime at) => !at.isBefore(issuedAt) && at.isBefore(expiresAt);

  bool covers(DataClass dataClass) => scopes.contains(dataClass);

  /// Full-identity comparison. `issue` uses this, not `expiresAt` alone: a
  /// same-expiry re-issue must not be able to swap the grantee or widen scope.
  bool sameGrantAs(ConsentToken o) =>
      id == o.id &&
      patientId == o.patientId &&
      grantedToActorId == o.grantedToActorId &&
      grantorId == o.grantorId &&
      purpose == o.purpose &&
      scopes.length == o.scopes.length &&
      scopes.containsAll(o.scopes) &&
      issuedAt == o.issuedAt &&
      expiresAt == o.expiresAt &&
      type == o.type;

  Map<String, Object?> toJson() => {
        'id': id,
        'patientId': patientId,
        'to': grantedToActorId,
        'grantor': grantorId,
        'purpose': purpose.name,
        'scopes': [for (final s in scopes) s.name],
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'type': type.name,
      };

  static ConsentToken fromJson(Map<String, Object?> j) => ConsentToken(
        id: j['id']! as String,
        patientId: j['patientId']! as String,
        grantedToActorId: j['to']! as String,
        grantorId: j['grantor']! as String,
        purpose: GrantPurpose.values.byName(j['purpose']! as String),
        scopes: {for (final s in j['scopes']! as List) DataClass.values.byName(s as String)},
        issuedAt: DateTime.parse(j['issuedAt']! as String),
        expiresAt: DateTime.parse(j['expiresAt']! as String),
        type: GrantType.values.byName(j['type']! as String),
      );
}
