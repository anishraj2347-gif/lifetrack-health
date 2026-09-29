import '../../audit/audit_log.dart';
import '../../consent/consent_token.dart';
import '../../consent/record_access.dart';
import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../plane_a/banned_phrases.dart';
import 'pseudonymised_slice.dart';

/// Remote kill switch for Tier 2. Takes the clock as a parameter — a
/// staleness check that reads wall time cannot be tested deterministically,
/// and the last one silently rotted a test suite overnight.
abstract interface class TierPolicy {
  bool tier2Enabled(String regionCode, DateTime at);
}

/// Tier 2 is dark until Phase 5 certification.
class DisabledTierPolicy implements TierPolicy {
  const DisabledTierPolicy();
  @override
  bool tier2Enabled(String regionCode, DateTime at) => false;
}

/// A fetched policy. Fails closed once older than [maxStaleness].
class RemoteTierPolicy implements TierPolicy {
  RemoteTierPolicy({required this.enabledRegions, required this.fetchedAt, this.maxStaleness = const Duration(hours: 6)});
  final Set<String> enabledRegions;
  final DateTime fetchedAt;
  final Duration maxStaleness;

  @override
  bool tier2Enabled(String regionCode, DateTime at) =>
      at.difference(fetchedAt) <= maxStaleness && !at.isBefore(fetchedAt) && enabledRegions.contains(regionCode);
}

/// Proof that a person tapped, once, recently, having been shown [disclosure].
///
/// Bound to the disclosure: the payload that leaves must be byte-identical to
/// what the patient read.
class HumanAction {
  HumanAction({required this.surface, required this.tappedAt, required this.disclosure});

  static const maxAge = Duration(seconds: 60);

  final String surface;
  final DateTime tappedAt;
  final String disclosure;
  bool _spent = false;

  bool get isSpent => _spent;

  /// Synchronous check-and-spend. There is no `await` between the check and
  /// the flag, so two concurrent sends on one tap cannot both pass.
  void consume(DateTime at) {
    if (_spent) throw const CloudRefused('This tap has already been used.');
    if (at.isBefore(tappedAt) || at.difference(tappedAt) > maxAge) {
      throw const CloudRefused('Too long since you tapped. Please confirm again.');
    }
    _spent = true;
  }
}

abstract interface class CloudClient {
  Future<List<String>> analyse(String payload);
}

/// The release build has no INTERNET permission; there is no client to use.
class UnavailableCloudClient implements CloudClient {
  const UnavailableCloudClient();
  @override
  Future<List<String>> analyse(String payload) =>
      Future.error(const CloudRefused('Cloud analysis is not available in this version.'));
}

class CloudRefused implements Exception {
  const CloudRefused(this.message);
  final String message;
  @override
  String toString() => 'CloudRefused: $message';
}

class CloudResult {
  const CloudResult({required this.statements, required this.dropped});
  final List<String> statements;

  /// Statements removed for banned phrasing. Dropped, never rephrased.
  final int dropped;
}

/// Plane C's only door out. Gates, in order:
///  1. kill switch (with the caller's clock)
///  2. the human tap — fresh, unspent, spent now
///  3. Plane C's own one-time grant, via `RecordAccess` (authorize + audit)
///  4. the payload equals the disclosure the patient saw
///  5. an `cloudEgress` audit entry — before the send
class CloudGateway {
  CloudGateway({required this.access, required this.audit, required this.policy, required this.client});

  final RecordAccess access;
  final AuditLog audit;
  final TierPolicy policy;
  final CloudClient client;

  Future<CloudResult> analyse({
    required Patient patient,
    required String regionCode,
    required HumanAction action,
    required String tokenId,
    required DateTime now,
  }) async {
    if (!policy.tier2Enabled(regionCode, now)) {
      throw const CloudRefused('Cloud analysis is switched off.');
    }
    action.consume(now);
    final records = await access.read(
      tokenId: tokenId,
      actorId: Actors.cloud,
      patientId: patient.id,
      dataClass: DataClass.reports,
      purpose: GrantPurpose.cloudAnalysis,
      at: now,
    );
    final slice = PseudonymisedSlice.fromRecords(patient: patient, records: records, at: now);
    if (slice.canonical != action.disclosure) {
      throw const CloudRefused('Your records changed after you reviewed them. Please review again.');
    }
    await audit.append(AuditEntry(
      at: now,
      actorId: Actors.cloud,
      patientId: patient.id,
      action: AuditAction.cloudEgress,
      dataClass: DataClass.reports,
      tokenId: tokenId,
      detail: '${slice.entries.length} values, no identifiers',
    ));
    final raw = await client.analyse(slice.canonical);
    final kept = [for (final s in raw) if (firstBannedPhrase(s) == null) s];
    return CloudResult(statements: kept, dropped: raw.length - kept.length);
  }
}
