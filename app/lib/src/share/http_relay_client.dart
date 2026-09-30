import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

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
