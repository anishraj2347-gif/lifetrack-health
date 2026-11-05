import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../crypto/vault_codec.dart' show VaultAuthenticationFailed, VaultLockedOut, VaultTooLarge;
import '../identity/identity_verifier.dart';
import '../identity/lifetrack_ids.dart';
import '../vault/backup_vault.dart';
import 'relay.dart';

/// How long any call may take. A server that has gone quiet must not hold a
/// screen, a queue or a retry for ever.
class NetTimeouts {
  const NetTimeouts({this.quick = const Duration(seconds: 20), this.share = const Duration(seconds: 60), this.bulk = const Duration(minutes: 5)});

  /// Small requests.
  final Duration quick;

  /// A share of up to 5 MB, or a mailbox of them.
  final Duration share;

  /// A whole backup, up or down.
  final Duration bulk;
}

/// The ONLY file in the patient app that talks to a network (CLAUDE.md #3).
/// It carries ciphertext, mailbox ids and hashes of tokens — never a record
/// in the clear, because nothing in the clear is ever handed to it.
///
/// `plane_boundary_test.dart` pins this as the single importer of
/// `package:http`, and `platform_config_test.dart` pins the one INTERNET
/// permission it needs. Moving either is a custody event.
class HttpRelayClient implements RelayClient {
  HttpRelayClient({required this.baseUrl, required this.tokens, http.Client? client, this.timeouts = const NetTimeouts()}) : _http = client ?? http.Client();

  /// e.g. `http://127.0.0.1:8787` in local development (phone over
  /// `adb reverse`); an https URL in any real deployment.
  final Uri baseUrl;
  final http.Client _http;
  final NetTimeouts timeouts;

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
    ).timeout(timeouts.share);
    if (r.statusCode != 201) throw RelayUnavailable('Share not delivered (${r.statusCode}).');
  }

  @override
  Future<void> withdraw({required String mailbox, required String grantId}) async {
    // Spent only once the relay has answered: offline, it must survive to be
    // used by the retry.
    final token = await tokens.peek(grantId);
    if (token == null) return;
    final r = await _http.delete(baseUrl.resolve(RelayApi.itemPath(mailbox, grantId)), headers: {RelayApi.hWithdrawToken: token}).timeout(timeouts.quick);
    if (r.statusCode != 200) throw RelayUnavailable('Share not withdrawn (${r.statusCode}).');
    await tokens.take(grantId);
  }

  @override
  Future<List<Uint8List>> collect({required String mailbox, required String secret}) async {
    final r = await _http.get(baseUrl.resolve(RelayApi.mailboxPath(mailbox)), headers: {RelayApi.hMailboxSecret: secret}).timeout(timeouts.share);
    if (r.statusCode != 200) throw RelayUnavailable('Could not check for prescriptions (${r.statusCode}).');
    final items = ((jsonDecode(r.body) as Map)['items'] as List?) ?? const [];
    return [for (final i in items) base64Decode((i as Map)['envelope']! as String)];
  }
}

abstract interface class WithdrawTokenStore {
  Future<void> put(String grantId, String token);

  /// Reads without removing.
  Future<String?> peek(String grantId);
  Future<String?> take(String grantId);
}

class InMemoryWithdrawTokens implements WithdrawTokenStore {
  final Map<String, String> _t = {};
  @override
  Future<void> put(String grantId, String token) async => _t[grantId] = token;
  @override
  Future<String?> peek(String grantId) async => _t[grantId];
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
  HttpRemoteVaultStore({required this.baseUrl, http.Client? client, this.timeouts = const NetTimeouts()}) : _http = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;
  final NetTimeouts timeouts;

  Uri _u(String account, [String rest = '']) => baseUrl.resolve('/v1/vault/${Uri.encodeComponent(account)}$rest');

  Future<http.Response> _call(Future<http.Response> Function() f, {Duration? within}) async {
    try {
      return await f().timeout(within ?? timeouts.quick);
    } on Object {
      throw const RelayUnavailable('Could not reach the backup service.');
    }
  }

  /// A backup's JSON is the largest thing the app handles: it is built on
  /// another isolate and sent as bytes, so nothing on screen waits for it.
  static Future<Uint8List> _encode(RemoteVaultEntry entry) => Isolate.run(() => utf8.encode(jsonEncode({
        'salt': base64Encode(entry.salt),
        'verifier': base64Encode(entry.verifier),
        'wrappedDataKey': base64Encode(entry.wrappedDataKey),
        'blob': base64Encode(entry.blob),
      })));

  static Future<Map<Object?, Object?>> _decode(Uint8List body) => Isolate.run(() => jsonDecode(utf8.decode(body)) as Map);

  @override
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier}) async {
    final body = await _encode(entry);
    final r = await _call(() async {
      final req = http.Request('PUT', _u(account))
        ..headers.addAll({'content-type': 'application/json', if (currentVerifier != null) RelayApi.hVerifier: base64Encode(currentVerifier)})
        ..bodyBytes = body;
      return http.Response.fromStream(await _http.send(req));
    }, within: timeouts.bulk);
    if (r.statusCode == 403) throw const VaultAuthenticationFailed();
    if (r.statusCode == 413) throw const VaultTooLarge();
    if (r.statusCode != 200 && r.statusCode != 201) throw RelayUnavailable('The backup service did not save it (${r.statusCode}). LifeTrack will try again.');
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
        headers: {'content-type': 'application/json'}, body: jsonEncode({'verifier': base64Encode(verifier)})), within: timeouts.bulk);
    if (r.statusCode == 429) throw const VaultLockedOut();
    if (r.statusCode == 403 || r.statusCode == 404) throw const VaultAuthenticationFailed();
    if (r.statusCode != 200) throw RelayUnavailable('Backup service error (${r.statusCode}).');
    final j = await _decode(r.bodyBytes);
    return (base64Decode(j['wrappedDataKey']! as String), base64Decode(j['blob']! as String));
  }

  @override
  Future<Uint8List?> blob(String account) async {
    final r = await _call(() => _http.get(_u(account, '/blob')), within: timeouts.bulk);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw RelayUnavailable('Backup service error (${r.statusCode}).');
    return base64Decode((await _decode(r.bodyBytes))['blob']! as String);
  }

  @override
  Future<void> delete(String account, List<int> verifier) async {
    final r = await _call(() => _http.delete(_u(account), headers: {RelayApi.hVerifier: base64Encode(verifier)}));
    if (r.statusCode == 403) throw const VaultAuthenticationFailed();
    if (r.statusCode != 200) throw RelayUnavailable('Backup not deleted (${r.statusCode}).');
  }
}

/// Asks the registry whether a doctor is still approved with the same keys.
class HttpDoctorStatus implements DoctorStatus {
  HttpDoctorStatus({required this.baseUrl, http.Client? client, this.timeouts = const NetTimeouts()}) : _http = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;
  final NetTimeouts timeouts;

  @override
  Future<bool?> stillApproved(DoctorCertificate cert) async {
    try {
      final r = await _http.get(baseUrl.resolve('/v1/doctors/${Uri.encodeComponent(cert.registryId)}')).timeout(timeouts.quick);
      if (r.statusCode == 404) return false;
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map;
      return j['status'] == 'approved' && j['keyId'] == await cert.keyId();
    } on Object {
      return null;
    }
  }
}

/// LifeTrack ID registration on the LifeTrack server.
class HttpIdDirectory implements IdDirectory {
  HttpIdDirectory({required this.baseUrl, http.Client? client, this.timeouts = const NetTimeouts()}) : _http = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;
  final NetTimeouts timeouts;

  @override
  Future<bool> register({required String id, required String mailbox, required List<int> key, required String tokenHash, IdentityAttestation? attestation, bool sample = false}) async {
    final r = await _http.post(baseUrl.resolve('/v1/ids'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'id': id, 'mailbox': mailbox, 'key': base64Encode(key), 'tokenHash': tokenHash, 'attestation': ?attestation?.toJson(), if (sample) 'sample': true})).timeout(timeouts.quick);
    if (r.statusCode == 409) {
      if ((jsonDecode(r.body) as Map)['reason'] == 'person_exists') throw const PersonExists();
      return false;
    }
    if (r.statusCode != 201) throw RelayUnavailable('LifeTrack ID not registered (${r.statusCode}).');
    return true;
  }

  @override
  Future<void> move({required String id, required String token, required String mailbox, required List<int> key}) async {
    final r = await _http.put(baseUrl.resolve('/v1/ids/$id'),
        headers: {'content-type': 'application/json', RelayApi.hIdToken: token}, body: jsonEncode({'mailbox': mailbox, 'key': base64Encode(key)})).timeout(timeouts.quick);
    if (r.statusCode != 200) throw RelayUnavailable('LifeTrack ID not moved (${r.statusCode}).');
  }

  @override
  Future<void> delete({required String id, required String token}) async {
    final r = await _http.delete(baseUrl.resolve('/v1/ids/$id'), headers: {RelayApi.hIdToken: token}).timeout(timeouts.quick);
    if (r.statusCode == 403) throw const IdNotYours();
    if (r.statusCode != 200) throw RelayUnavailable('LifeTrack ID not deleted (${r.statusCode}).');
  }

  @override
  Future<String> reclaim({required String mailbox, required List<int> key, required String tokenHash, required IdentityAttestation attestation}) async {
    final r = await _http.post(baseUrl.resolve('/v1/ids/reclaim'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'mailbox': mailbox, 'key': base64Encode(key), 'tokenHash': tokenHash, 'attestation': attestation.toJson()})).timeout(timeouts.quick);
    if (r.statusCode == 200) return (jsonDecode(r.body) as Map)['id']! as String;
    if (r.statusCode == 403 || r.statusCode == 404) throw ReclaimRefused('${(jsonDecode(r.body) as Map)['error']}');
    throw RelayUnavailable('LifeTrack ID not moved (${r.statusCode}).');
  }
}

/// The DigiLocker check, run by the LifeTrack server (which holds the
/// DigiLocker partner secret). The phone only starts it and collects the
/// signed result.
class HttpIdentityVerifier implements IdentityVerifier {
  HttpIdentityVerifier({required this.baseUrl, http.Client? client, this.timeouts = const NetTimeouts()}) : _http = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;
  final NetTimeouts timeouts;

  /// Whether the server offers identity checks at all.
  Future<bool> available() async {
    try {
      final r = await _http.get(baseUrl.resolve('/v1/verify/config')).timeout(timeouts.quick);
      return r.statusCode == 200 && (jsonDecode(r.body) as Map)['enabled'] == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<VerifySession> start({required String purpose, IdentityAttestation? parent}) async {
    final http.Response r;
    try {
      r = await _http.post(baseUrl.resolve('/v1/verify/start'),
          headers: {'content-type': 'application/json'}, body: jsonEncode({'purpose': purpose, 'parent': ?parent?.toJson()})).timeout(timeouts.quick);
    } on Object {
      throw const VerificationFailed('Could not reach LifeTrack to start the DigiLocker check.');
    }
    final j = jsonDecode(r.body) as Map;
    if (r.statusCode != 200) throw VerificationFailed('${j['error'] ?? 'The DigiLocker check could not start.'}');
    return VerifySession(id: j['session']! as String, secret: j['secret']! as String, authorizeUrl: Uri.parse(j['authorizeUrl']! as String));
  }

  @override
  Future<Map<String, Object?>> poll(VerifySession s, {String? code}) async {
    try {
      final path = baseUrl.resolve('/v1/verify/${Uri.encodeComponent(s.id)}');
      final r = await _http.get(code == null ? path : path.replace(queryParameters: {'code': code}), headers: {RelayApi.hSessionSecret: s.secret}).timeout(timeouts.quick);
      return (jsonDecode(r.body) as Map).cast();
    } on Object {
      return {'status': 'pending'};
    }
  }
}
