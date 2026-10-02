import 'dart:convert';
import 'dart:io';

import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// Encrypted backups, one file per account. The server holds the salt, a
/// hash of the login verifier, the wrapped data key and the sealed blob —
/// enough for an offline guess at a weak password, which is why the app
/// generates a strong one. It never holds a key that opens a blob.
///
/// Only a SHA-256 of the verifier is kept, so a copy of this folder is not
/// itself the proof that updates or deletes a backup.
class VaultStore {
  VaultStore(this.dir);
  final Directory dir;

  /// Failed proofs per account in the current hour — on open, replace and
  /// delete alike: an online guesser gets [maxFailuresPerHour] tries, not
  /// millions. Kept on disk so a restart does not reset the count.
  Map<String, (DateTime, int)>? _failures;
  static const maxFailuresPerHour = 10;

  static bool validAccount(String a) => RegExp(r'^LT-[0-9A-Z]{5}-[0-9A-Z]{5}$').hasMatch(a);

  File _file(String account) => File('${dir.path}/$account.json');
  File get _failuresFile => File('${dir.path}/_failures.json');

  Future<Map<String, Object?>?> get(String account) async {
    final f = _file(account);
    if (!await f.exists()) return null;
    return (jsonDecode(await f.readAsString()) as Map).cast();
  }

  /// Atomic: write a temp file, flush, rename over the old one.
  Future<void> put(String account, Map<String, Object?> entry) async {
    await dir.create(recursive: true);
    final tmp = File('${_file(account).path}.tmp');
    await tmp.writeAsString(jsonEncode(entry), flush: true);
    await tmp.rename(_file(account).path);
  }

  Future<bool> delete(String account) async {
    final f = _file(account);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// The stored form of a verifier (base64 as the phone sends it).
  static Future<String> hashVerifier(String verifier) => RelayApi.sha256Hex('lifetrack/vault-verifier|$verifier');

  /// Whether [given] proves [entry]'s password. Entries written before
  /// hashing hold the raw verifier; a correct proof against one of those is
  /// reported with `migrate: true` so the caller rewrites it hashed.
  static Future<({bool ok, bool migrate})> check(Map<String, Object?> entry, String? given) async {
    if (given == null) return (ok: false, migrate: false);
    final hashed = entry['verifierHash'] as String?;
    if (hashed != null) return (ok: sameText(await hashVerifier(given), hashed), migrate: false);
    final ok = sameText(given, entry['verifier'] as String?);
    return (ok: ok, migrate: ok);
  }

  /// Same comparison time whatever the input, so a guesser learns nothing
  /// from how long a refusal takes.
  static bool sameText(String? a, String? b) {
    if (a == null || b == null || a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  Future<Map<String, (DateTime, int)>> _loadFailures() async {
    if (_failures != null) return _failures!;
    final m = <String, (DateTime, int)>{};
    try {
      if (await _failuresFile.exists()) {
        for (final e in (jsonDecode(await _failuresFile.readAsString()) as Map).entries) {
          final v = e.value as Map;
          m[e.key as String] = (DateTime.parse(v['since']! as String), v['n']! as int);
        }
      }
    } on Object {
      // A damaged counter file starts the count again; it never blocks.
    }
    return _failures = m;
  }

  Future<void> _saveFailures(DateTime now) async {
    final m = _failures!..removeWhere((_, v) => now.difference(v.$1) >= const Duration(hours: 1));
    await dir.create(recursive: true);
    final tmp = File('${_failuresFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({for (final e in m.entries) e.key: {'since': e.value.$1.toIso8601String(), 'n': e.value.$2}}), flush: true);
    await tmp.rename(_failuresFile.path);
  }

  Future<bool> lockedOut(String account, DateTime now) async {
    final f = (await _loadFailures())[account];
    return f != null && now.difference(f.$1) < const Duration(hours: 1) && f.$2 >= maxFailuresPerHour;
  }

  Future<void> failed(String account, DateTime now) async {
    final m = await _loadFailures();
    final f = m[account];
    m[account] = f == null || now.difference(f.$1) >= const Duration(hours: 1) ? (now, 1) : (f.$1, f.$2 + 1);
    await _saveFailures(now);
  }

  Future<void> succeeded(String account, DateTime now) async {
    if ((await _loadFailures()).remove(account) != null) await _saveFailures(now);
  }
}
