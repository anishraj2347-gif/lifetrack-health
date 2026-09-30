import '../model/health_record.dart';
import 'consent_token.dart';

/// Why an authorization was refused. Surfaced in the audit entry for the
/// denied attempt, so the patient sees refusals as well as successes.
enum DenialReason { unknown, revoked, notYetValid, expired, spent, wrongPatient, wrongActor, wrongPurpose, outOfScope }

class ConsentDenied implements Exception {
  ConsentDenied(this.reason, this.tokenId);
  final DenialReason reason;
  final String tokenId;
  @override
  String toString() => 'ConsentDenied(${reason.name}, $tokenId)';
}

/// Raised when `issue` would change a live grant in place — extend it, swap
/// its grantee, or widen it (CLAUDE.md #11b, #12).
class ConsentConflict implements Exception {
  ConsentConflict(this.tokenId);
  final String tokenId;
  @override
  String toString() => 'ConsentConflict($tokenId): revoke the live grant before issuing a different one.';
}

/// The single authority on which grants exist.
///
/// `authorize` resolves the **stored** token by id and checks that — never the
/// object a caller hands in. The caller supplies only an id and a description
/// of what it is trying to do; every property that decides the outcome comes
/// from the store.
///
/// Issuing is a human act (CLAUDE.md #5): no file under `lib/src/ai/` may call
/// [issue], and `plane_boundary_test.dart` enforces it.
class ConsentStore {
  ConsentStore({this.onChanged});

  /// Called after every mutation so the owner can persist the new state.
  final void Function(ConsentStore store)? onChanged;

  final Map<String, ConsentToken> _issued = {};
  final Set<String> _revoked = {};
  final Set<String> _spent = {};

  /// Records a grant a human has just approved.
  ///
  /// Re-issuing an identical live grant is a no-op. Re-issuing a *different*
  /// grant under a live id throws. An id whose grant has expired, been revoked
  /// or been spent is evicted first, so the same doctor can be approved again
  /// on a later day.
  void issue(ConsentToken token, {required DateTime at}) {
    final existing = _issued[token.id];
    if (existing != null) {
      if (_isFinished(existing, at)) {
        _evict(existing.id);
      } else if (existing.sameGrantAs(token)) {
        return;
      } else {
        throw ConsentConflict(token.id);
      }
    }
    _issued[token.id] = token;
    onChanged?.call(this);
  }

  /// Validates an attempted use of grant [tokenId] and returns the stored
  /// grant. Spends a one-time grant as part of the same synchronous step, so
  /// two concurrent callers cannot both pass (there is no `await` between the
  /// check and the spend).
  ConsentToken authorize({
    required String tokenId,
    required String actorId,
    required String patientId,
    required DataClass dataClass,
    required GrantPurpose purpose,
    required DateTime at,
  }) {
    final t = _issued[tokenId];
    if (t == null) throw ConsentDenied(DenialReason.unknown, tokenId);
    if (_revoked.contains(tokenId)) throw ConsentDenied(DenialReason.revoked, tokenId);
    if (_spent.contains(tokenId)) throw ConsentDenied(DenialReason.spent, tokenId);
    if (at.isBefore(t.issuedAt)) throw ConsentDenied(DenialReason.notYetValid, tokenId);
    if (!at.isBefore(t.expiresAt)) throw ConsentDenied(DenialReason.expired, tokenId);
    if (t.patientId != patientId) throw ConsentDenied(DenialReason.wrongPatient, tokenId);
    if (t.grantedToActorId != actorId) throw ConsentDenied(DenialReason.wrongActor, tokenId);
    if (t.purpose != purpose) throw ConsentDenied(DenialReason.wrongPurpose, tokenId);
    if (!t.covers(dataClass)) throw ConsentDenied(DenialReason.outOfScope, tokenId);
    if (t.type == GrantType.oneTime) {
      _spent.add(tokenId);
      onChanged?.call(this);
    }
    return t;
  }

  /// Revocation is the one ending the patient controls. Always permitted,
  /// always immediate.
  void revoke(String tokenId) {
    if (!_issued.containsKey(tokenId)) return;
    _revoked.add(tokenId);
    onChanged?.call(this);
  }

  ConsentToken? lookup(String tokenId) => _issued[tokenId];

  /// Grants the patient can still revoke — shown on the Share screen.
  List<ConsentToken> activeGrantsFor(String patientId, DateTime at) => [
        for (final t in _issued.values)
          if (t.patientId == patientId && !_isFinished(t, at)) t,
      ]..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));

  /// Whether a grant to [actorId] bound to [granteeKeyId] was issued for
  /// [patientId] since [since] — live or finished (finished grants are kept
  /// until [evictFinished]). Used to accept a prescription only from a doctor
  /// the patient recently shared with.
  bool everIssuedTo({required String patientId, required String actorId, required String granteeKeyId, required DateTime since}) =>
      _issued.values.any((t) =>
          t.patientId == patientId &&
          t.grantedToActorId == actorId &&
          t.granteeKeyId == granteeKeyId &&
          !t.issuedAt.isBefore(since));

  /// Drops every finished grant. Safe at any time: a finished grant can never
  /// authorize again, and its history lives in the audit log, not here.
  ///
  /// Kept for [kMaxGrantWindow] after it ends, so a doctor's prescription
  /// sent just after a visit can still be matched to that visit.
  void evictFinished(DateTime at) {
    final dead = [
      for (final t in _issued.values)
        if (_isFinished(t, at) && at.difference(t.expiresAt.isBefore(at) ? t.expiresAt : t.issuedAt) > kMaxGrantWindow) t.id,
    ];
    if (dead.isEmpty) return;
    dead.forEach(_evict);
    onChanged?.call(this);
  }

  /// Removes every grant for [patientId] — part of erasure.
  void eraseFor(String patientId) {
    final ids = [for (final t in _issued.values) if (t.patientId == patientId) t.id];
    ids.forEach(_evict);
    onChanged?.call(this);
  }

  bool _isFinished(ConsentToken t, DateTime at) =>
      _revoked.contains(t.id) || _spent.contains(t.id) || !at.isBefore(t.expiresAt);

  void _evict(String id) {
    _issued.remove(id);
    _revoked.remove(id);
    _spent.remove(id);
  }

  Map<String, Object?> toJson() => {
        'issued': [for (final t in _issued.values) t.toJson()],
        'revoked': _revoked.toList(),
        'spent': _spent.toList(),
      };

  void restore(Map<String, Object?> j) {
    _issued
      ..clear()
      ..addEntries([
        for (final t in (j['issued'] as List?) ?? const [])
          MapEntry((t as Map)['id']! as String, ConsentToken.fromJson(t.cast<String, Object?>())),
      ]);
    _revoked
      ..clear()
      ..addAll([for (final r in (j['revoked'] as List?) ?? const []) r as String]);
    _spent
      ..clear()
      ..addAll([for (final s in (j['spent'] as List?) ?? const []) s as String]);
  }
}
