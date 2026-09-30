import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../crypto/vault_codec.dart' show VaultAuthenticationFailed, VaultLockedOut;
import '../vault/backup_vault.dart';
import 'relay.dart';

/// The ONLY file in the patient app that talks to a network (CLAUDE.md #3).
/// It carries ciphertext, mailbox ids and hashes of tokens — never a record
/// in the clear, because nothing in the clear is ever handed to it.
///
/// `plane_boundary_test.dart` pins this as the single importer of
/// `package:http`, and `platform_config_test.dart` pins the one INTERNET
/// permission it needs. Moving either is a custody event.
class HttpRelayClient implements RelayClient {
  HttpRelayClient({required this.baseUrl, required this.tokens, http.Client? client}) : _http = client ?? http.Client();

  /// e.g. `http://127.0.0.1:8787` in local development (phone over
  /// `adb reverse`); an https URL in any real deployment.
  final Uri baseUrl;
  final http.Client _http;

  /// Withdraw tokens, kept on the phone so a share can be pulled back after
  /// a restart. Keyed by grant id.
  final WithdrawTokenStore tokens;

  @override
  Future<void> deposit({required String mailbox, required String grantId, required Uint8List envelope, required DateTime expiresAt}) async {
    final token = RelayApi.newToken();
    await tokens.put(grantId, token);
    final r = await _http.put(
      baseUrl.resolve(RelayApi.itemPath(mailbox, grantId)),
      body: envelope,
      headers: {
        RelayApi.hExpires: expiresAt.toUtc().toIso8601String(),
        RelayApi.hWithdrawHash: await RelayApi.sha256Hex(token),
        'content-type': 'application/octet-stream',
      },
    );
    if (r.statusCode != 201) throw RelayUnavailable('Share not delivered (${r.statusCode}).');
  }

  @override
  Future<void> withdraw({required String mailbox, required String grantId}) async {
    final token = await tokens.take(grantId);
    if (token == null) return;
    await _http.delete(baseUrl.resolve(RelayApi.itemPath(mailbox, grantId)), headers: {RelayApi.hWithdrawToken: token});
  }

  @override
  Future<List<Uint8List>> collect({required String mailbox, required String secret}) async {
    final r = await _http.get(baseUrl.resolve(RelayApi.mailboxPath(mailbox)), headers: {RelayApi.hMailboxSecret: secret});
    if (r.statusCode != 200) throw RelayUnavailable('Could not check for prescriptions (${r.statusCode}).');
    final items = ((jsonDecode(r.body) as Map)['items'] as List?) ?? const [];
    return [for (final i in items) base64Decode((i as Map)['envelope']! as String)];
  }
}

abstract interface class WithdrawTokenStore {
  Future<void> put(String grantId, String token);
  Future<String?> take(String grantId);
}

class InMemoryWithdrawTokens implements WithdrawTokenStore {
  final Map<String, String> _t = {};
  @override
  Future<void> put(String grantId, String token) async => _t[grantId] = token;
  @override
  Future<String?> take(String grantId) async => _t.remove(grantId);
}

class RelayUnavailable implements Exception {
  const RelayUnavailable(this.message);
  final String message;
  @override
  String toString() => 'RelayUnavailable: $message';
}

/// The backup store on the same LifeTrack server as the relay. Everything it
/// sends is already sealed on the phone; the password never leaves it — only
/// the verifier derived from it.
class HttpRemoteVaultStore implements RemoteVaultStore {
  HttpRemoteVaultStore({required this.baseUrl, http.Client? client}) : _http = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  Uri _u(String account, [String rest = '']) => baseUrl.resolve('/v1/vault/${Uri.encodeComponent(account)}$rest');

  Future<http.Response> _call(Future<http.Response> Function() f) async {
    try {
      return await f();
    } on Object {
      throw const RelayUnavailable('Could not reach the backup service.');
    }
  }

  @override
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier}) async {
    final r = await _call(() => _http.put(
          _u(account),
          headers: {'content-type': 'application/json', if (currentVerifier != null) RelayApi.hVerifier: base64Encode(currentVerifier)},
          body: jsonEncode({
            'salt': base64Encode(entry.salt),
            'verifier': base64Encode(entry.verifier),
            'wrappedDataKey': base64Encode(entry.wrappedDataKey),
            'blob': base64Encode(entry.blob),
          }),
        ));
    if (r.statusCode == 403) throw const VaultAuthenticationFailed();
    if (r.statusCode != 200 && r.statusCode != 201) throw RelayUnavailable('Backup not saved (${r.statusCode}).');
  }

  @override
  Future<List<int>?> salt(String account) async {
    final r = await _call(() => _http.get(_u(account, '/salt')));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw RelayUnavailable('Backup service error (${r.statusCode}).');
    return base64Decode((jsonDecode(r.body) as Map)['salt']! as String);
  }

  @override
  Future<(Uint8List, Uint8List)> open(String account, List<int> verifier) async {
    final r = await _call(() => _http.post(_u(account, '/open'),
        headers: {'content-type': 'application/json'}, body: jsonEncode({'verifier': base64Encode(verifier)})));
    if (r.statusCode == 429) throw const VaultLockedOut();
    if (r.statusCode == 403 || r.statusCode == 404) throw const VaultAuthenticationFailed();
    if (r.statusCode != 200) throw RelayUnavailable('Backup service error (${r.statusCode}).');
    final j = jsonDecode(r.body) as Map;
    return (base64Decode(j['wrappedDataKey']! as String), base64Decode(j['blob']! as String));
  }

  @override
  Future<Uint8List?> blob(String account) async {
    final r = await _call(() => _http.get(_u(account, '/blob')));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw RelayUnavailable('Backup service error (${r.statusCode}).');
    return base64Decode((jsonDecode(r.body) as Map)['blob']! as String);
  }

  @override
  Future<void> delete(String account, List<int> verifier) async {
    final r = await _call(() => _http.delete(_u(account), headers: {RelayApi.hVerifier: base64Encode(verifier)}));
    if (r.statusCode == 403) throw const VaultAuthenticationFailed();
    if (r.statusCode != 200) throw RelayUnavailable('Backup not deleted (${r.statusCode}).');
  }
}
