/// Why a profile's records are on this phone, and on whose authority.
///
/// Every profile on the phone has one. It decides who may grant access to
/// its records and how that is recorded (CLAUDE.md #14: proxy consent only
/// for dependents, and the grantor is always recorded).
enum CustodyKind {
  /// The phone owner's own profile.
  self,

  /// A child under 18; the custodian is their parent (DPDP s.9).
  childOfParent,

  /// A capable adult who asked the custodian to keep and share their
  /// records for them — revocable at any time.
  delegatedByAdult,
}

/// How the authority was given. Stated plainly on screen, including what is
/// NOT yet verified.
enum ConsentMethod {
  /// The custodian declared they are the child's parent. Verification (e.g.
  /// DigiLocker) is not connected yet.
  parentDeclaration,

  /// The adult read the statement on the custodian's phone and typed their
  /// name. OTP to their own number is not connected yet.
  inPersonOnCustodianPhone,
}

class Custody {
  const Custody({
    required this.patientId,
    required this.kind,
    required this.custodianId,
    required this.relation,
    this.method,
    this.consentedAt,
    this.statement,
    this.signedName,
    this.endedAt,
  });

  /// The profile this custody is about.
  final String patientId;
  final CustodyKind kind;

  /// The phone owner's own profile id — the person acting for this one.
  final String custodianId;

  /// Relation of this profile to the custodian: "son", "mother", …
  final String relation;
  final ConsentMethod? method;
  final DateTime? consentedAt;

  /// The exact words agreed to, kept as they were shown.
  final String? statement;

  /// For a delegation: the name the adult typed to confirm.
  final String? signedName;

  /// When a delegation was ended. An ended custody grants nothing.
  final DateTime? endedAt;

  bool get isActive => endedAt == null;

  bool get isVerified => false; // No verification service is connected yet.

  Custody ended(DateTime at) => Custody(
        patientId: patientId,
        kind: kind,
        custodianId: custodianId,
        relation: relation,
        method: method,
        consentedAt: consentedAt,
        statement: statement,
        signedName: signedName,
        endedAt: at,
      );

  Map<String, Object?> toJson() => {
        'patientId': patientId,
        'kind': kind.name,
        'custodianId': custodianId,
        'relation': relation,
        'method': method?.name,
        'consentedAt': consentedAt?.toIso8601String(),
        'statement': statement,
        'signedName': signedName,
        'endedAt': endedAt?.toIso8601String(),
      };

  static Custody fromJson(Map<String, Object?> j) => Custody(
        patientId: j['patientId']! as String,
        kind: CustodyKind.values.byName(j['kind']! as String),
        custodianId: j['custodianId']! as String,
        relation: j['relation']! as String,
        method: j['method'] == null ? null : ConsentMethod.values.byName(j['method']! as String),
        consentedAt: j['consentedAt'] == null ? null : DateTime.parse(j['consentedAt']! as String),
        statement: j['statement'] as String?,
        signedName: j['signedName'] as String?,
        endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt']! as String),
      );

  /// The statement an adult agrees to when asking someone to manage their
  /// records. Plain words; shown and stored exactly.
  static String delegationStatement({required String adultName, required String custodianName}) =>
      'I, $adultName, ask $custodianName to keep my medical records on their phone and to show them to my doctors when I ask. '
      'I can stop this at any time, and my records then stop being shared on my behalf.';
}

/// Why acting for a profile was refused.
class CustodyRefused implements Exception {
  const CustodyRefused(this.message);
  final String message;
  @override
  String toString() => 'CustodyRefused: $message';
}
