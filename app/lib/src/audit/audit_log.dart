import '../model/health_record.dart';
import '../storage/sealed_store.dart';

enum AuditAction {
  view,
  edit,
  denied,
  grantIssued,
  grantRevoked,

  /// A Plane C slice left the phone. Written *before* the send, so a failed
  /// send is still recorded — an audit written only on success is an audit
  /// of successes.
  cloudEgress,

  /// An approved clinical share left the phone, encrypted to one doctor's
  /// device key. Written before the send (CLAUDE.md #1c).
  clinicalShare,

  /// A signed prescription from a verified doctor was added to the record.
  prescriptionReceived,

  /// Someone read the Emergency ID card without unlocking the phone.
  emergencyRead,
  vaultBackup,
  vaultRestore,
  erasure,

  /// The patient exported an unencrypted copy of their records to hand to
  /// another app of their choosing. Written before the file is handed over.
  export,
}

class AuditEntry {
  const AuditEntry({
    required this.at,
    required this.actorId,
    required this.patientId,
    required this.action,
    this.dataClass,
    this.tokenId,
    this.detail,
  });

  final DateTime at;
  final String actorId;
  final String patientId;
  final AuditAction action;
  final DataClass? dataClass;

  /// The grant that authorised this action — the entry's lawful basis.
  final String? tokenId;
  final String? detail;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'actor': actorId,
        'patient': patientId,
        'action': action.name,
        'class': dataClass?.name,
        'token': tokenId,
        'detail': detail,
      };

  static AuditEntry fromJson(Map<String, Object?> j) => AuditEntry(
        at: DateTime.parse(j['at']! as String),
        actorId: j['actor']! as String,
        patientId: j['patient']! as String,
        action: AuditAction.values.byName(j['action']! as String),
        dataClass: j['class'] == null ? null : DataClass.values.byName(j['class']! as String),
        tokenId: j['token'] as String?,
        detail: j['detail'] as String?,
      );
}

/// Append-only: the interface has no update and no delete.
///
/// What it does *not* promise: tamper-proofing against someone with the
/// unlocked phone and a debugger. Screens describe it as a log the app never
/// edits, not as one nobody could (CLAUDE.md #9b).
abstract interface class AuditLog {
  Future<void> append(AuditEntry entry);
  List<AuditEntry> entriesFor(String patientId);
}

class InMemoryAuditLog implements AuditLog {
  final List<AuditEntry> _entries = [];

  @override
  Future<void> append(AuditEntry entry) async => _entries.add(entry);

  @override
  List<AuditEntry> entriesFor(String patientId) =>
      List.unmodifiable(_entries.where((e) => e.patientId == patientId).toList().reversed);
}

/// Durable log, sealed under the device key. Survives the process being
/// killed — CLAUDE.md #13a requires append-only *and* durable.
class PersistentAuditLog implements AuditLog {
  PersistentAuditLog._(this._store, this._entries);

  static const blobName = 'audit_log';
  final SealedStore _store;
  final List<AuditEntry> _entries;

  static Future<PersistentAuditLog> open(SealedStore store) async {
    final body = await store.read(blobName) as List?;
    return PersistentAuditLog._(store, [
      for (final e in body ?? const []) AuditEntry.fromJson((e as Map).cast<String, Object?>()),
    ]);
  }

  @override
  Future<void> append(AuditEntry entry) async {
    _entries.add(entry);
    await _store.write(blobName, [for (final e in _entries) e.toJson()]);
  }

  @override
  List<AuditEntry> entriesFor(String patientId) =>
      List.unmodifiable(_entries.where((e) => e.patientId == patientId).toList().reversed);

  /// Erasure removes the patient's own history along with their records. The
  /// erasure itself is then the first entry of an otherwise empty log.
  Future<void> eraseFor(String patientId, AuditEntry erasureEntry) async {
    _entries.removeWhere((e) => e.patientId == patientId);
    await append(erasureEntry);
  }
}
