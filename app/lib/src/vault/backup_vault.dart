import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../audit/audit_log.dart';
import '../crypto/key_derivation.dart';
import '../crypto/shamir.dart';
import '../crypto/vault_codec.dart';
import '../model/health_record.dart';

/// Server side of the backup. Holds ciphertext, the wrapped data key, the
/// salt and the login verifier — together an offline guessing oracle for the
/// passphrase (Mechanisms fig. 2). That is why no screen may claim LifeTrack
/// is unable to open a backup.
///
/// No implementation talks to a network yet: the release build has no
/// INTERNET permission and there is no server.
abstract interface class RemoteVaultStore {
  Future<void> put(String account, RemoteVaultEntry entry);
  Future<RemoteVaultEntry?> fetch(String account, List<int> loginVerifier);
  Future<RemoteVaultEntry?> fetchForShareRecovery(String account);

  /// Erasure (DPDP §12). Deletes everything held for [account].
  Future<void> delete(String account);
}

class RemoteVaultEntry {
  const RemoteVaultEntry({required this.salt, required this.verifier, required this.wrappedDataKey, required this.blob});
  final List<int> salt;
  final List<int> verifier;
  final Uint8List wrappedDataKey;
  final Uint8List blob;
}

class InMemoryRemoteVaultStore implements RemoteVaultStore {
  final Map<String, RemoteVaultEntry> _entries = {};

  @override
  Future<void> put(String account, RemoteVaultEntry entry) async => _entries[account] = entry;

  @override
  Future<RemoteVaultEntry?> fetch(String account, List<int> loginVerifier) async {
    final e = _entries[account];
    if (e == null || !_constantTimeEquals(e.verifier, loginVerifier)) return null;
    return e;
  }

  @override
  Future<RemoteVaultEntry?> fetchForShareRecovery(String account) async => _entries[account];

  @override
  Future<void> delete(String account) async => _entries.remove(account);

  bool get isEmpty => _entries.isEmpty;

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

class VaultSetup {
  const VaultSetup({required this.shares});

  /// Three shares of the data key, any two of which open the backup. One
  /// stays on this phone, one is printed, one goes to a trusted contact.
  /// LifeTrack keeps none of them.
  final List<Share> shares;
}

/// Encrypted, patient-keyed backup of doctor-issued documents (blueprint §5.2).
class BackupVault {
  BackupVault({required this.remote, required this.audit, required this.params});

  final RemoteVaultStore remote;
  final AuditLog audit;
  final KdfParams params;

  static final _aead = AesGcm.with256bits();

  /// Creates the vault and backs up [records]. Personal notes are included
  /// only if [includeNotes].
  Future<VaultSetup> create({
    required String account,
    required String patientId,
    required String passphrase,
    required List<HealthRecord> records,
    required DateTime at,
    bool includeNotes = false,
  }) async {
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final dataKeyBytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final keys = await VaultKeyDerivation.derive(passphrase, salt, params);
    final wrapped = await _aead.encrypt(dataKeyBytes, secretKey: keys.vaultKey);
    final blob = await VaultCodec.seal(
      [for (final r in records) if (r.backedUpByDefault || includeNotes) r.toJson()],
      SecretKey(dataKeyBytes),
    );
    await remote.put(
      account,
      RemoteVaultEntry(salt: salt, verifier: keys.loginVerifier, wrappedDataKey: Uint8List.fromList(wrapped.concatenation()), blob: blob),
    );
    await audit.append(AuditEntry(
      at: at,
      actorId: 'patient:$patientId',
      patientId: patientId,
      action: AuditAction.vaultBackup,
      detail: '${records.where((r) => r.backedUpByDefault || includeNotes).length} documents',
    ));
    return VaultSetup(shares: Shamir.split(dataKeyBytes, threshold: 2, count: 3));
  }

  Future<List<HealthRecord>> restoreWithPassphrase({
    required String account,
    required String patientId,
    required String passphrase,
    required List<int> salt,
    required DateTime at,
  }) async {
    final keys = await VaultKeyDerivation.derive(passphrase, salt, params);
    final entry = await remote.fetch(account, keys.loginVerifier);
    if (entry == null) throw const VaultAuthenticationFailed();
    final box = SecretBox.fromConcatenation(entry.wrappedDataKey, nonceLength: 12, macLength: 16);
    final List<int> dataKey;
    try {
      dataKey = await _aead.decrypt(box, secretKey: keys.vaultKey);
    } on SecretBoxAuthenticationError {
      throw const VaultAuthenticationFailed();
    }
    return _open(entry.blob, dataKey, patientId, at, 'passphrase');
  }

  Future<List<HealthRecord>> restoreWithShares({
    required String account,
    required String patientId,
    required List<Share> shares,
    required DateTime at,
  }) async {
    final entry = await remote.fetchForShareRecovery(account);
    if (entry == null) throw const VaultAuthenticationFailed();
    return _open(entry.blob, Shamir.combine(shares), patientId, at, 'recovery shares');
  }

  /// Salt lookup for the passphrase path. Served before authentication, which
  /// is part of the oracle described above.
  Future<List<int>?> saltFor(String account) async => (await remote.fetchForShareRecovery(account))?.salt;

  Future<List<HealthRecord>> _open(Uint8List blob, List<int> dataKey, String patientId, DateTime at, String how) async {
    final body = await VaultCodec.open(blob, SecretKey(dataKey)) as List;
    final records = [
      for (final r in body)
        HealthRecord.fromJson((r as Map).cast<String, Object?>()).copyWith(source: RecordSource.restoredFromBackup),
    ];
    // A restore reads the entire record set; it belongs in "who opened what".
    await audit.append(AuditEntry(
      at: at,
      actorId: 'patient:$patientId',
      patientId: patientId,
      action: AuditAction.vaultRestore,
      detail: '${records.length} documents, via $how',
    ));
    return records;
  }

  Future<void> erase(String account) => remote.delete(account);
}
