import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../audit/audit_log.dart';
import '../crypto/key_derivation.dart';
import '../crypto/shamir.dart';
import '../crypto/vault_codec.dart';

/// Server side of the backup. Holds ciphertext, the wrapped data key, the
/// salt and the login verifier — together an offline guessing oracle for the
/// password (Mechanisms fig. 2). That is why the app generates the password
/// and no screen may claim LifeTrack is unable to open a backup.
abstract interface class RemoteVaultStore {
  /// Creates the backup, or replaces it when [currentVerifier] proves the
  /// password it was made with.
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier});

  /// Served before any proof; null when there is no backup.
  Future<List<int>?> salt(String account);

  /// The wrapped key and blob, for the right verifier. Throws
  /// [VaultAuthenticationFailed] or [VaultLockedOut].
  Future<(Uint8List wrappedDataKey, Uint8List blob)> open(String account, List<int> verifier);

  /// The sealed blob only, for recovery with shares; null when none.
  Future<Uint8List?> blob(String account);

  /// Erasure (DPDP §12).
  Future<void> delete(String account, List<int> verifier);
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

  bool get isEmpty => _entries.isEmpty;

  @override
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier}) async {
    final e = _entries[account];
    if (e != null && (currentVerifier == null || !constantTimeEquals(e.verifier, currentVerifier))) throw const VaultAuthenticationFailed();
    _entries[account] = entry;
  }

  @override
  Future<List<int>?> salt(String account) async => _entries[account]?.salt;

  @override
  Future<(Uint8List, Uint8List)> open(String account, List<int> verifier) async {
    final e = _entries[account];
    if (e == null || !constantTimeEquals(e.verifier, verifier)) throw const VaultAuthenticationFailed();
    return (e.wrappedDataKey, e.blob);
  }

  @override
  Future<Uint8List?> blob(String account) async => _entries[account]?.blob;

  @override
  Future<void> delete(String account, List<int> verifier) async {
    final e = _entries[account];
    if (e == null) return;
    if (!constantTimeEquals(e.verifier, verifier)) throw const VaultAuthenticationFailed();
    _entries.remove(account);
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

/// Everything a phone needs to keep backing up to the same account without
/// the password: kept sealed under the device key, never shown.
class VaultKeys {
  const VaultKeys({required this.dataKey, required this.salt, required this.verifier, required this.wrappedDataKey});
  final List<int> dataKey;
  final List<int> salt;
  final List<int> verifier;
  final Uint8List wrappedDataKey;

  Map<String, Object?> toJson() => {
        'dataKey': _b64(dataKey),
        'salt': _b64(salt),
        'verifier': _b64(verifier),
        'wrapped': _b64(wrappedDataKey),
      };

  static VaultKeys fromJson(Map<String, Object?> j) => VaultKeys(
        dataKey: _unb64(j['dataKey']! as String),
        salt: _unb64(j['salt']! as String),
        verifier: _unb64(j['verifier']! as String),
        wrappedDataKey: Uint8List.fromList(_unb64(j['wrapped']! as String)),
      );

  static String _b64(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  static List<int> _unb64(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
}

class VaultSetup {
  const VaultSetup({required this.keys, required this.shares});
  final VaultKeys keys;

  /// Three shares of the data key, any two of which open the backup. One
  /// stays on this phone, one is printed, one goes to a trusted contact.
  /// LifeTrack keeps none of them.
  final List<Share> shares;
}

/// What a restore returns: the backed-up snapshot, and the keys to keep
/// backing up to the same account from this phone.
class VaultRestore {
  const VaultRestore({required this.body, required this.keys});
  final Map<String, Object?> body;
  final VaultKeys keys;
}

/// Encrypted, patient-keyed backup (blueprint §5.2). The body is whatever the
/// app snapshots; this class only seals, stores and opens it.
class BackupVault {
  BackupVault({required this.remote, required this.audit, required this.params});

  final RemoteVaultStore remote;
  final AuditLog audit;
  final KdfParams params;

  static final _aead = AesGcm.with256bits();

  /// A new backup under [password]. The keys go inside the sealed body too,
  /// so a phone restored with shares can keep backing up without it.
  Future<VaultSetup> create({
    required String account,
    required String password,
    required Map<String, Object?> body,
    required String auditPatientId,
    required String detail,
    required DateTime at,
  }) async {
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final dataKey = List<int>.generate(32, (_) => rng.nextInt(256));
    final derived = await VaultKeyDerivation.derive(password, salt, params);
    final wrapped = await _aead.encrypt(dataKey, secretKey: derived.vaultKey);
    final keys = VaultKeys(dataKey: dataKey, salt: salt, verifier: derived.loginVerifier, wrappedDataKey: Uint8List.fromList(wrapped.concatenation()));
    await remote.put(account, await _entry(keys, body));
    await _log(auditPatientId, AuditAction.vaultBackup, 'backup made: $detail', at);
    return VaultSetup(keys: keys, shares: Shamir.split(dataKey, threshold: 2, count: 3));
  }

  /// Replaces the backup's contents; the password and shares stay valid.
  Future<void> update({
    required String account,
    required VaultKeys keys,
    required Map<String, Object?> body,
    required String auditPatientId,
    required String detail,
    required DateTime at,
  }) async {
    await remote.put(account, await _entry(keys, body), currentVerifier: keys.verifier);
    await _log(auditPatientId, AuditAction.vaultBackup, 'backed up: $detail', at);
  }

  Future<VaultRestore> restoreWithPassword({required String account, required String password, required String auditPatientId, required DateTime at}) async {
    final salt = await remote.salt(account);
    if (salt == null) throw const VaultAuthenticationFailed();
    final derived = await VaultKeyDerivation.derive(password, salt, params);
    final (wrappedBytes, blob) = await remote.open(account, derived.loginVerifier);
    final List<int> dataKey;
    try {
      dataKey = await _aead.decrypt(SecretBox.fromConcatenation(wrappedBytes, nonceLength: 12, macLength: 16), secretKey: derived.vaultKey);
    } on SecretBoxAuthenticationError {
      throw const VaultAuthenticationFailed();
    }
    return _open(blob, dataKey, auditPatientId, at, 'password');
  }

  Future<VaultRestore> restoreWithShares({required String account, required List<Share> shares, required String auditPatientId, required DateTime at}) async {
    final blob = await remote.blob(account);
    if (blob == null) throw const VaultAuthenticationFailed();
    return _open(blob, Shamir.combine(shares), auditPatientId, at, 'recovery codes');
  }

  Future<void> erase(String account, VaultKeys keys) => remote.delete(account, keys.verifier);

  Future<RemoteVaultEntry> _entry(VaultKeys keys, Map<String, Object?> body) async => RemoteVaultEntry(
        salt: keys.salt,
        verifier: keys.verifier,
        wrappedDataKey: keys.wrappedDataKey,
        blob: await VaultCodec.seal({...body, '_keys': keys.toJson()}, SecretKey(keys.dataKey)),
      );

  Future<VaultRestore> _open(Uint8List blob, List<int> dataKey, String auditPatientId, DateTime at, String how) async {
    final body = ((await VaultCodec.open(blob, SecretKey(dataKey))) as Map).cast<String, Object?>();
    final keys = VaultKeys.fromJson((body.remove('_keys')! as Map).cast());
    // A restore reads the entire record set; it belongs in "who opened what".
    await _log(auditPatientId, AuditAction.vaultRestore, 'restored with $how', at);
    return VaultRestore(body: body, keys: keys);
  }

  Future<void> _log(String patientId, AuditAction action, String detail, DateTime at) =>
      audit.append(AuditEntry(at: at, actorId: 'patient:$patientId', patientId: patientId, action: action, detail: detail));
}
