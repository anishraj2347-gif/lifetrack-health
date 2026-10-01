import '../model/health_record.dart';

/// Why a grant exists. Part of the token's identity, not a label on it: a
/// grant for on-device insight building may not be spent on a cloud egress,
/// and the audit entry's stated lawful basis is read from here (CLAUDE.md #11).
enum GrantPurpose { clinicalConsult, onDeviceInsights, cloudAnalysis }

/// One-time grants are spent by their first successful authorization (walk-in
/// QR, Plane C tap). Session grants live until they expire or are revoked.
enum GrantType { oneTime, session }

/// What a doctor asks for and a patient approves (CLAUDE.md #16). A level is
/// a preset over data classes; it never widens `authorize` beyond them.
enum AccessLevel {
  /// Allergies, conditions, active medicines, the latest result per test.
  /// The default: it is the level that prevents repeat tests.
  summary,

  /// Every report, prescription and scan, optionally filtered.
  allReports,

  /// Family illnesses as the patient knows them ("patient-reported").
  familyIllnesses,

  /// Blood pressure and sugar the patient measured at home, last 30 days.
  homeReadings,
}

Set<DataClass> scopesFor(Set<AccessLevel> levels) => {
      for (final l in levels)
        ...switch (l) {
          AccessLevel.summary => const {DataClass.allergies, DataClass.conditions, DataClass.prescriptions, DataClass.reports},
          AccessLevel.allReports => const {
              DataClass.allergies,
              DataClass.conditions,
              DataClass.prescriptions,
              DataClass.reports,
              DataClass.scans,
            },
          AccessLevel.familyIllnesses => const {DataClass.familyHistory},
          AccessLevel.homeReadings => const {DataClass.vitals},
        },
    };

/// Narrows what a grant releases: a date range and/or named tests. Applied
/// when the share is built; never widens the scopes.
class RecordFilter {
  const RecordFilter({this.from, this.to, this.analytes});
  final DateTime? from;
  final DateTime? to;
  final Set<String>? analytes;

  bool get isEmpty => from == null && to == null && (analytes == null || analytes!.isEmpty);

  bool admitsDate(DateTime d) => (from == null || !d.isBefore(from!)) && (to == null || !d.isAfter(to!));

  @override
  bool operator ==(Object other) =>
      other is RecordFilter &&
      other.from == from &&
      other.to == to &&
      ((other.analytes ?? const {}).length == (analytes ?? const {}).length) &&
      (other.analytes ?? const {}).containsAll(analytes ?? const {});

  @override
  int get hashCode => Object.hash(from, to, (analytes ?? const {}).length);

  Map<String, Object?> toJson() => {
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'analytes': analytes?.toList(),
      };

  static RecordFilter? fromJson(Object? j) {
    if (j == null) return null;
    final m = (j as Map).cast<String, Object?>();
    return RecordFilter(
      from: m['from'] == null ? null : DateTime.parse(m['from']! as String),
      to: m['to'] == null ? null : DateTime.parse(m['to']! as String),
      analytes: (m['analytes'] as List?)?.cast<String>().toSet(),
    );
  }
}

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
    Set<AccessLevel> levels = const {},
    this.filter,
    this.granteeKeyId,
  })  : scopes = Set.unmodifiable(scopes),
        levels = Set.unmodifiable(levels) {
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

  /// The levels the patient approved — for the screen and the audit entry.
  /// `scopes` is what `authorize` enforces.
  final Set<AccessLevel> levels;
  final RecordFilter? filter;

  /// The doctor device key this grant's share is encrypted to. Set for
  /// clinical shares (CLAUDE.md #1a, #15); null for on-device grants.
  final String? granteeKeyId;

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
      type == o.type &&
      levels.length == o.levels.length &&
      levels.containsAll(o.levels) &&
      filter == o.filter &&
      granteeKeyId == o.granteeKeyId;

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
        if (levels.isNotEmpty) 'levels': [for (final l in levels) l.name],
        if (filter != null) 'filter': filter!.toJson(),
        if (granteeKeyId != null) 'key': granteeKeyId,
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
        levels: {for (final l in (j['levels'] as List?) ?? const []) AccessLevel.values.byName(l as String)},
        filter: RecordFilter.fromJson(j['filter']),
        granteeKeyId: j['key'] as String?,
      );
}
