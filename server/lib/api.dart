import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'guards.dart';
import 'registry.dart';
import 'relay_store.dart';
import 'id_registry.dart';
import 'identity.dart';
import 'vault_store.dart';

/// HTTP routes. Every response is JSON; no response ever contains a
/// decrypted record, because the server never holds a key that makes one.
class LifeTrackApi {
  LifeTrackApi({
    required this.registry,
    required this.relay,
    required this.vault,
    required this.ids,
    required this.adminToken,
    this.identity,
    this.requireIdentity = false,
    this.origins = const OriginPolicy(),
    this.publicBase,
    this.trustProxy = false,
    RateLimiter? limiter,
    DateTime Function()? clock,
  })  : clock = clock ?? DateTime.now,
        limiter = limiter ?? RateLimiter(clock: clock);

  final DoctorRegistry registry;
  final RelayStore relay;
  final VaultStore vault;
  final IdRegistry ids;

  /// DigiLocker-backed identity checks; null when not configured.
  final IdentityService? identity;

  /// When true, a LifeTrack ID is issued only with a signed identity
  /// attestation, and one person gets one ID.
  final bool requireIdentity;
  final String adminToken;
  final DateTime Function() clock;

  /// Which Host names and browser origins may call.
  final OriginPolicy origins;

  /// The address people reach this server at, for links the server hands
  /// out (the DigiLocker sign-in). Null: the request's own (already checked)
  /// host.
  final Uri? publicBase;

  /// Rate limits count per `X-Forwarded-For` client (see [clientOf]); set
  /// only when a reverse proxy you run sits in front.
  final bool trustProxy;
  final RateLimiter limiter;

  /// Body sizes. A backup carries every original page; a share up to 5 MB;
  /// everything else is a small JSON document.
  static const maxBackup = 60 * 1024 * 1024;
  static const maxShare = 5 * 1024 * 1024;
  static const maxJson = 64 * 1024;

  /// Per client address. Generous for a person; ruinous for a script.
  static final rateRules = [
    RateRule('POST', RegExp(r'^/v1/doctors$'), 10, const Duration(hours: 1)),
    RateRule('POST', RegExp(r'^/v1/ids$'), 30, const Duration(hours: 1)),
    RateRule('GET', RegExp(r'^/v1/ids/'), 60, const Duration(minutes: 1)),
    RateRule('POST', RegExp(r'^/v1/verify/start$'), 30, const Duration(hours: 1)),
    RateRule('GET', RegExp(r'^/v1/verify/'), 120, const Duration(minutes: 1)),
    RateRule('PUT', RegExp(r'^/v1/relay/'), 120, const Duration(minutes: 1)),
    RateRule('GET', RegExp(r'^/v1/relay/'), 120, const Duration(minutes: 1)),
    RateRule('GET', RegExp(r'^/v1/vault/'), 30, const Duration(minutes: 1)),
    // Opening, replacing and deleting a backup prove a password; each
    // account also locks after 10 wrong proofs an hour (VaultStore).
    RateRule('POST', RegExp(r'^/v1/vault/[^/]+/open$'), 20, const Duration(hours: 1)),
    RateRule('PUT', RegExp(r'^/v1/vault/'), 120, const Duration(hours: 1)),
    RateRule('DELETE', RegExp(r'^/v1/vault/'), 20, const Duration(hours: 1)),
    RateRule('POST', RegExp(r'^/v1/admin/'), 60, const Duration(minutes: 1)),
    RateRule('GET', RegExp(r'^/v1/admin/'), 60, const Duration(minutes: 1)),
  ];

  /// Signed pickups already used, until they could no longer pass the time
  /// check anyway.
  final Map<String, DateTime> _seenPickups = {};

  Handler get handler {
    final r = Router()
      ..get('/v1/health', (Request _) => _json({'ok': true}))
      ..get('/v1/registry/key', _registryKey)
      ..post('/v1/doctors', _enrol)
      ..get('/v1/doctors/<reg>', _doctor)
      ..get('/v1/admin/doctors', _adminList)
      ..post('/v1/admin/doctors/<reg>/approve', _adminApprove)
      ..post('/v1/admin/doctors/<reg>/reject', _adminReject)
      ..post('/v1/admin/doctors/<reg>/revoke', _adminRevoke)
      ..put('/v1/relay/<mailbox>/<grant>', _deposit)
      ..delete('/v1/relay/<mailbox>/<grant>', _withdraw)
      ..get('/v1/relay/<mailbox>', _pickup)
      ..put('/v1/vault/<account>', _vaultPut)
      ..get('/v1/vault/<account>/salt', _vaultSalt)
      ..post('/v1/vault/<account>/open', _vaultOpen)
      ..get('/v1/vault/<account>/blob', _vaultBlob)
      ..delete('/v1/vault/<account>', _vaultDelete)
      ..post('/v1/ids', _idRegister)
      ..get('/v1/ids/<id>', _idLookup)
      ..put('/v1/ids/<id>', _idMove)
      ..delete('/v1/ids/<id>', _idDelete)
      ..get('/v1/verify/config', _verifyConfig)
      ..post('/v1/verify/start', _verifyStart)
      ..get('/v1/verify/callback', _verifyCallback)
      ..get('/v1/verify/<session>', _verifyPoll)
      ..get('/v1/practice-digilocker/authorize', _practiceAuthorize)
      ..get('/v1/practice-digilocker/approve', _practiceApprove);
    return const Pipeline()
        .addMiddleware(origins.middleware())
        .addMiddleware(rateLimit(limiter, rateRules, trustProxy: trustProxy))
        .addHandler(r.call);
  }

  /// A small JSON object from the body; null when it is too large or not a
  /// JSON object.
  static Future<Map<String, Object?>?> _readJson(Request req) async {
    final raw = await readCapped(req, maxJson);
    if (raw == null) return null;
    try {
      return (jsonDecode(utf8.decode(raw)) as Map).cast();
    } on Object {
      return null;
    }
  }

  static String _bounded(Object? v, {int max = 200}) {
    final s = (v! as String).trim();
    if (s.isEmpty || s.length > max) throw ArgumentError('Each field must be 1–$max characters.');
    return s;
  }

  // ---- registry ------------------------------------------------------------

  Future<Response> _registryKey(Request _) async =>
      _json({'publicKey': base64Encode((await registry.publicKey()).bytes), 'algorithm': 'Ed25519'});

  Future<Response> _enrol(Request req) async {
    final b = await _readJson(req);
    if (b == null) return _error(400, 'Invalid enrolment.');
    try {
      final e = await registry.enrol(
        registrationNo: _bounded(b['registrationNo'], max: 20).toUpperCase(),
        name: _bounded(b['name']),
        speciality: _bounded(b['speciality']),
        council: _bounded(b['council']),
        encryptionKey: base64Decode(b['encryptionKey']! as String),
        signingKey: base64Decode(b['signingKey']! as String),
        at: clock(),
      );
      return _json(e.publicJson(), status: 202);
    } on StateError catch (e) {
      return _error(409, e.message);
    } on Object catch (e) {
      return _error(400, e is ArgumentError ? '${e.message}' : 'Invalid enrolment.');
    }
  }

  /// Public: status, key fingerprint and — when approved — a certificate,
  /// renewed here when it is near expiry. Phones ask this to learn whether a
  /// doctor is still approved with the same keys.
  Future<Response> _doctor(Request _, String reg) async {
    final e = await registry.current(reg.toUpperCase(), clock());
    return e == null ? _error(404, 'Not enrolled.') : _json(e.publicJson());
  }

  bool _isAdmin(Request req) => VaultStore.sameText(req.headers[RelayApi.hAdmin], adminToken);

  Response _adminList(Request req) {
    if (!_isAdmin(req)) return _error(401, 'Admin token required.');
    return _json({
      for (final s in EnrolmentStatus.values) s.name: [for (final e in registry.withStatus(s)) e.publicJson()],
    });
  }

  Future<Response> _adminApprove(Request req, String reg) async {
    if (!_isAdmin(req)) return _error(401, 'Admin token required.');
    try {
      return _json((await registry.approve(reg.toUpperCase(), clock())).publicJson());
    } on StateError catch (e) {
      return _error(409, e.message);
    }
  }

  Future<Response> _adminReject(Request req, String reg) async {
    if (!_isAdmin(req)) return _error(401, 'Admin token required.');
    final b = await _readJson(req) ?? const {};
    final reason = b['reason'] is String ? _bounded(b['reason'], max: 500) : 'Licence could not be verified.';
    try {
      await registry.reject(reg.toUpperCase(), reason);
    } on StateError catch (e) {
      return _error(404, e.message);
    }
    return _json({'ok': true});
  }

  Future<Response> _adminRevoke(Request req, String reg) async {
    if (!_isAdmin(req)) return _error(401, 'Admin token required.');
    try {
      await registry.revoke(reg.toUpperCase());
    } on StateError catch (e) {
      return _error(404, e.message);
    }
    return _json({'ok': true});
  }

  // ---- relay ---------------------------------------------------------------

  static bool _validGrant(String g) => g.isNotEmpty && g.length <= 200;

  Future<Response> _deposit(Request req, String mailbox, String grant) async {
    if (!_validMailbox(mailbox)) return _error(400, 'Unknown mailbox.');
    final grantId = Uri.decodeComponent(grant);
    if (!_validGrant(grantId)) return _error(400, 'Invalid share id.');
    final exp = DateTime.tryParse(req.headers[RelayApi.hExpires] ?? '');
    final now = clock();
    if (exp == null || !exp.isAfter(now)) return _error(400, 'Missing or past expiry.');
    if (exp.difference(now) > RelayApi.maxHold) return _error(400, 'Expiry beyond 48 hours.');
    final raw = await readCapped(req, maxShare);
    if (raw == null || raw.isEmpty) return _error(413, 'Share too large.');
    try {
      relay.put(mailbox, grantId, RelayItem(envelope: Uint8List.fromList(raw), expiresAt: exp, withdrawHash: req.headers[RelayApi.hWithdrawHash]));
    } on RelayFull catch (e) {
      return _error(507, e.message);
    }
    return _json({'ok': true}, status: 201);
  }

  Future<Response> _withdraw(Request req, String mailbox, String grant) async {
    final token = req.headers[RelayApi.hWithdrawToken];
    if (token == null) return _error(401, 'Withdraw token required.');
    final ok = relay.withdraw(mailbox, Uri.decodeComponent(grant), await RelayApi.sha256Hex(token));
    // Same answer whether it was never there, already picked up, or removed:
    // the relay does not reveal delivery status to a guesser.
    return ok ? _json({'withdrawn': true}) : _json({'withdrawn': false});
  }

  Future<Response> _pickup(Request req, String mailbox) async {
    final now = clock();
    if (mailbox.startsWith('p-')) {
      final secret = req.headers[RelayApi.hMailboxSecret];
      if (secret == null || !VaultStore.sameText(await RelayApi.patientMailboxFor(secret), mailbox)) return _error(403, 'Not your mailbox.');
    } else if (mailbox.startsWith('d-')) {
      final problem = await _doctorAuth(req, mailbox, now);
      if (problem != null) return _error(403, problem);
    } else {
      return _error(400, 'Unknown mailbox.');
    }
    final items = relay.takeAll(mailbox, now);
    return _json({
      'items': [for (final (g, env) in items) {'grantId': g, 'envelope': base64Encode(env)}],
    });
  }

  Future<String?> _doctorAuth(Request req, String mailbox, DateTime now) async {
    final qr = req.headers[RelayApi.hCert];
    final time = DateTime.tryParse(req.headers[RelayApi.hTime] ?? '');
    final sig = req.headers[RelayApi.hSig];
    final nonce = req.headers[RelayApi.hNonce];
    if (qr == null || time == null || sig == null || nonce == null || nonce.isEmpty || nonce.length > 100) return 'Signed request required.';
    if (now.difference(time).abs() > RelayApi.signatureSkew) return 'Request time too far from server time.';
    final DoctorCertificate cert;
    try {
      cert = await (await registry.trust()).verify(qr, now);
    } on CertificateRejected catch (e) {
      return e.patientMessage;
    } on Object {
      return 'This is not a LifeTrack doctor code.';
    }
    if (registry.isRevoked(cert)) return 'Certificate revoked.';
    if (await RelayApi.doctorMailbox(cert.encryptionKey) != mailbox) return 'Mailbox does not belong to this certificate.';
    final bool ok;
    try {
      ok = await Ed25519().verify(
        RelayApi.pickupMessage(mailbox, time, nonce),
        signature: Signature(base64Decode(sig), publicKey: SimplePublicKey(cert.signingKey, type: KeyPairType.ed25519)),
      );
    } on Object {
      return 'Bad signature.';
    }
    if (!ok) return 'Bad signature.';
    // One use per signed request: a copy of it, replayed, is refused.
    _seenPickups.removeWhere((_, until) => !now.isBefore(until));
    final key = '$mailbox|$nonce';
    if (_seenPickups.containsKey(key)) return 'This request was already used.';
    _seenPickups[key] = time.add(RelayApi.signatureSkew * 2);
    return null;
  }

  static bool _validMailbox(String m) => RegExp(r'^(d|p)-[0-9a-f]{16,64}$').hasMatch(m);

  // ---- backup vault --------------------------------------------------------

  /// Proves the password with its verifier; counts a wrong proof towards the
  /// lockout. Returns an error response, or null when the proof is good.
  Future<Response?> _proveVault(String account, Map<String, Object?> entry, String? given, DateTime now) async {
    if (await vault.lockedOut(account, now)) return _error(429, 'Too many wrong passwords. Try again in an hour.');
    final c = await VaultStore.check(entry, given);
    if (!c.ok) {
      await vault.failed(account, now);
      return _error(403, 'Wrong account code or password.');
    }
    await vault.succeeded(account, now);
    if (c.migrate) {
      await vault.put(account, {...entry..remove('verifier'), 'verifierHash': await VaultStore.hashVerifier(given!)});
    }
    return null;
  }

  /// Creates a backup, or replaces it when the caller proves the current
  /// password with its verifier.
  Future<Response> _vaultPut(Request req, String account) async {
    final now = clock();
    if (!VaultStore.validAccount(account)) return _error(400, 'Unknown account format.');
    final existing = await vault.get(account);
    if (existing != null) {
      final refused = await _proveVault(account, existing, req.headers[RelayApi.hVerifier], now);
      if (refused != null) {
        return refused.statusCode == 403 ? _error(403, 'This backup belongs to someone else, or the password is wrong.') : refused;
      }
    }
    final raw = await readCapped(req, maxBackup);
    if (raw == null) return _error(413, 'Backup too large.');
    final Map<String, Object?> b;
    try {
      b = (jsonDecode(utf8.decode(raw)) as Map).cast();
      for (final k in ['salt', 'verifier', 'wrappedDataKey', 'blob']) {
        base64Decode(b[k]! as String);
      }
    } on Object {
      return _error(400, 'Invalid backup.');
    }
    await vault.put(account, {
      'salt': b['salt'],
      'verifierHash': await VaultStore.hashVerifier(b['verifier']! as String),
      'wrappedDataKey': b['wrappedDataKey'],
      'blob': b['blob'],
      'updatedAt': now.toIso8601String(),
    });
    return _json({'ok': true}, status: existing == null ? 201 : 200);
  }

  /// Served before any proof — the salt is needed to derive the proof.
  Future<Response> _vaultSalt(Request _, String account) async {
    final e = VaultStore.validAccount(account) ? await vault.get(account) : null;
    return e == null ? _error(404, 'No backup for this account code.') : _json({'salt': e['salt']});
  }

  Future<Response> _vaultOpen(Request req, String account) async {
    final now = clock();
    if (!VaultStore.validAccount(account)) return _error(400, 'Unknown account format.');
    if (await vault.lockedOut(account, now)) return _error(429, 'Too many wrong passwords. Try again in an hour.');
    final e = await vault.get(account);
    final given = (await _readJson(req))?['verifier'];
    // No backup: nothing to guess at, so nothing is counted — counting
    // made-up account codes would grow the failure file without bound.
    // (Whether a code exists is no secret: the salt route answers 404.)
    if (e == null) return _error(403, 'Wrong account code or password.');
    final refused = await _proveVault(account, e, given is String ? given : null, now);
    if (refused != null) return refused;
    return _json({'wrappedDataKey': e['wrappedDataKey'], 'blob': e['blob'], 'updatedAt': e['updatedAt']});
  }

  /// For recovery with two recovery codes: the sealed blob only — no
  /// verifier, no wrapped key. Opening it needs two full-strength codes.
  Future<Response> _vaultBlob(Request _, String account) async {
    final e = VaultStore.validAccount(account) ? await vault.get(account) : null;
    return e == null ? _error(404, 'No backup for this account code.') : _json({'blob': e['blob'], 'updatedAt': e['updatedAt']});
  }

  Future<Response> _vaultDelete(Request req, String account) async {
    final e = VaultStore.validAccount(account) ? await vault.get(account) : null;
    if (e == null) return _json({'deleted': false});
    final refused = await _proveVault(account, e, req.headers[RelayApi.hVerifier], clock());
    if (refused != null) return refused.statusCode == 403 ? _error(403, 'Wrong password.') : refused;
    await vault.delete(account);
    return _json({'deleted': true});
  }

  // ---- LifeTrack IDs -------------------------------------------------------

  static bool _validKey(Object? k) {
    try {
      return base64Decode(k! as String).length == 32;
    } on Object {
      return false;
    }
  }

  /// Registers a new ID. A duplicate is refused, so the phone draws another.
  Future<Response> _idRegister(Request req) async {
    final b = await _readJson(req);
    if (b == null) return _error(400, 'Invalid registration.');
    final id = LifeTrackId.parse('${b['id']}');
    final tokenHash = b['tokenHash'];
    if (id == null ||
        !_validMailbox('${b['mailbox']}') ||
        !'${b['mailbox']}'.startsWith('p-') ||
        !_validKey(b['key']) ||
        tokenHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(tokenHash)) {
      return _error(400, 'Invalid registration.');
    }
    if (ids.contains(id)) return _error(409, 'That ID is taken.');
    String? subject;
    if (b['attestation'] is Map) {
      final IdentityAttestation a;
      try {
        a = IdentityAttestation.fromJson((b['attestation']! as Map).cast());
      } on Object {
        return _error(400, 'Invalid identity check.');
      }
      if (!await a.verifies(await registry.trust())) return _error(400, 'The identity check is not LifeTrack\'s.');
      subject = a.subjectHash;
      final existing = ids.bySubject(subject);
      if (existing != null) {
        return _json({'error': 'This person already has a LifeTrack ID. Restore it from backup instead of making a new one.', 'reason': 'person_exists'}, status: 409);
      }
    } else if (requireIdentity) {
      return _error(400, 'A verified identity is needed for a LifeTrack ID.');
    }
    await ids.put(id, {'mailbox': b['mailbox'], 'key': b['key'], 'tokenHash': tokenHash, 'subject': ?subject, 'createdAt': clock().toIso8601String()});
    return _json({'id': id}, status: 201);
  }

  static String? _parseId(String raw) {
    try {
      return LifeTrackId.parse(Uri.decodeComponent(raw));
    } on Object {
      return null;
    }
  }

  /// Where to send a request for this person. Public: it names a mailbox
  /// and a key, nothing about who they are. Rate-limited per client, so the
  /// ten-billion-number space cannot be walked.
  Response _idLookup(Request _, String raw) {
    final id = _parseId(raw);
    final e = id == null ? null : ids[id];
    return e == null ? _error(404, 'No such LifeTrack ID.') : _json({'id': id, 'mailbox': e['mailbox'], 'key': e['key']});
  }

  /// A restored phone points its ID at its new mailbox and key.
  Future<Response> _idMove(Request req, String raw) async {
    final id = _parseId(raw);
    final e = id == null ? null : ids[id];
    if (e == null) return _error(404, 'No such LifeTrack ID.');
    final token = req.headers[RelayApi.hIdToken];
    if (token == null || !VaultStore.sameText(await RelayApi.sha256Hex(token), e['tokenHash'] as String?)) return _error(403, 'Not your ID.');
    final b = await _readJson(req);
    if (b == null || !_validMailbox('${b['mailbox']}') || !'${b['mailbox']}'.startsWith('p-') || !_validKey(b['key'])) return _error(400, 'Invalid update.');
    await ids.put(id!, {...e, 'mailbox': b['mailbox'], 'key': b['key']});
    return _json({'ok': true});
  }

  Future<Response> _idDelete(Request req, String raw) async {
    final id = _parseId(raw);
    final e = id == null ? null : ids[id];
    if (e == null) return _json({'deleted': false});
    final token = req.headers[RelayApi.hIdToken];
    if (token == null || !VaultStore.sameText(await RelayApi.sha256Hex(token), e['tokenHash'] as String?)) return _error(403, 'Not your ID.');
    await ids.remove(id!);
    return _json({'deleted': true});
  }

  // ---- identity (DigiLocker) ----------------------------------------------

  Response _verifyConfig(Request _) => _json({'enabled': identity != null, 'provider': identity?.provider.name, 'required': requireIdentity});

  Future<Response> _verifyStart(Request req) async {
    final idn = identity;
    if (idn == null) return _error(404, 'Identity checks are not set up on this server.');
    final b = await _readJson(req);
    if (b == null) return _error(400, 'Invalid request.');
    final purpose = VerifyPurpose.values.where((v) => v.name == b['purpose']).firstOrNull;
    if (purpose == null) return _error(400, 'Unknown purpose.');
    try {
      final (id, secret, url) = await idn.start(
        base: publicBase ?? req.requestedUri.replace(path: '', query: null),
        purpose: purpose,
        parent: b['parent'] is Map ? IdentityAttestation.fromJson((b['parent']! as Map).cast()) : null,
      );
      return _json({'session': id, 'secret': secret, 'authorizeUrl': '$url'});
    } on VerifyRefused catch (e) {
      return _error(403, e.message);
    } on Object {
      return _error(400, 'Invalid request.');
    }
  }

  Future<Response> _verifyCallback(Request req) async {
    final idn = identity;
    if (idn == null) return _error(404, 'Identity checks are not set up on this server.');
    final q = req.requestedUri.queryParameters;
    String title;
    String body;
    String? code;
    try {
      final r = await idn.callback(state: q['state'] ?? '', code: q['code'], error: q['error']);
      code = r.handback;
      title = r.refused == null ? 'Verified — now go back to LifeTrack' : 'Not verified';
      body = r.refused == null
          ? 'Type this code into LifeTrack to finish. Do not give it to anyone else: whoever types it gets your verified name and date of birth.'
          : '${r.refused} Go back to LifeTrack to try again.';
    } on VerifyRefused catch (e) {
      title = 'Not verified';
      body = e.message;
    }
    const esc = HtmlEscape();
    return Response.ok(
      '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>LifeTrack</title></head>'
      '<body style="font:18px system-ui;padding:32px;background:#f4f4f2"><h2>${esc.convert(title)}</h2>'
      '${code == null ? '' : '<p style="font:600 34px ui-monospace,monospace;letter-spacing:4px;background:#fff;padding:16px 20px;border-radius:14px;display:inline-block">${esc.convert(code)}</p>'}'
      '<p>${esc.convert(body)}</p></body></html>',
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'referrer-policy': 'no-referrer',
        'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'",
      },
    );
  }

  Future<Response> _verifyPoll(Request req, String session) async {
    final secret = req.headers[RelayApi.hSessionSecret];
    final idn = identity;
    if (idn == null || secret == null) return _error(404, 'No such session.');
    return _json(await idn.poll(session, secret, code: req.requestedUri.queryParameters['code']));
  }

  Response _practiceAuthorize(Request req) {
    if (identity?.provider is! PracticeDigiLocker) return _error(404, 'Not here.');
    final q = req.requestedUri.queryParameters;
    return Response.ok(PracticeDigiLocker.page(state: q['state'] ?? '', challenge: q['challenge'] ?? '', purpose: q['purpose'] ?? 'self'),
        headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'"});
  }

  Response _practiceApprove(Request req) {
    final p = identity?.provider;
    if (p is! PracticeDigiLocker) return _error(404, 'Not here.');
    final q = req.requestedUri.queryParameters;
    if (!PracticeDigiLocker.accounts.containsKey(q['account'])) return _error(400, 'Unknown account.');
    final code = p.approve(q['account']!, q['challenge'] ?? '');
    return Response.found(req.requestedUri.replace(path: '/v1/verify/callback', queryParameters: {'state': q['state'] ?? '', 'code': code}));
  }

  // ---- helpers -------------------------------------------------------------

  static Response _json(Object body, {int status = 200}) =>
      Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json', 'cache-control': 'no-store'});

  static Response _error(int status, String message) => _json({'error': message}, status: status);
}
