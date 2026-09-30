import 'dart:convert';
import 'dart:io';

/// Encrypted backups, one file per account. The server holds the salt, the
/// login verifier, the wrapped data key and the sealed blob — enough for an
/// offline guess at a weak password, which is why the app generates a strong
/// one. It never holds a key that opens a blob.
class VaultStore {
  VaultStore(this.dir);
  final Directory dir;

  /// Failed opens per account in the current hour: an online guesser gets
  /// [maxFailuresPerHour] tries, not millions.
  final Map<String, (DateTime, int)> _failures = {};
  static const maxFailuresPerHour = 10;

  static bool validAccount(String a) => RegExp(r'^LT-[0-9A-Z]{5}-[0-9A-Z]{5}$').hasMatch(a);

  File _file(String account) => File('${dir.path}/$account.json');

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

  bool lockedOut(String account, DateTime now) {
    final f = _failures[account];
    return f != null && now.difference(f.$1) < const Duration(hours: 1) && f.$2 >= maxFailuresPerHour;
  }

  void failed(String account, DateTime now) {
    final f = _failures[account];
    _failures[account] = f == null || now.difference(f.$1) >= const Duration(hours: 1) ? (now, 1) : (f.$1, f.$2 + 1);
  }

  void succeeded(String account) => _failures.remove(account);
}
