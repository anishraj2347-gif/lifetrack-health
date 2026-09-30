import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'registry.dart';
import 'relay_store.dart';
import 'id_registry.dart';
import 'vault_store.dart';

/// HTTP routes. Every response is JSON; no response ever contains a
/// decrypted record, because the server never holds a key that makes one.
class LifeTrackApi {
  LifeTrackApi({required this.registry, required this.relay, required this.vault, required this.ids, required this.adminToken, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final DoctorRegistry registry;
  final RelayStore relay;
  final VaultStore vault;
  final IdRegistry ids;
  final String adminToken;
  final DateTime Function() clock;

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
      ..delete('/v1/ids/<id>', _idDelete);
    return const Pipeline().addMiddleware(_cors()).addHandler(r.call);
  }

  // ---- registry ------------------------------------------------------------

  Future<Response> _registryKey(Request _) async =>
      _json({'publicKey': base64Encode((await registry.publicKey()).bytes), 'algorithm': 'Ed25519'});

  Future<Response> _enrol(Request req) async {
    final Map<String, Object?> b;
    try {
      b = (jsonDecode(await req.readAsString()) as Map).cast();
      final e = await registry.enrol(
        registrationNo: (b['registrationNo']! as String).trim().toUpperCase(),
        name: (b['name']! as String).trim(),
        speciality: (b['speciality']! as String).trim(),
        council: (b['council']! as String).trim(),
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

  Response _doctor(Request _, String reg) {
    final e = registry.byRegistration(reg.toUpperCase());
    return e == null ? _error(404, 'Not enrolled.') : _json(e.publicJson());
  }

  bool _isAdmin(Request req) => req.headers[RelayApi.hAdmin] == adminToken;

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
    final reason = ((jsonDecode(await req.readAsString()) as Map)['reason'] as String?) ?? 'Licence could not be verified.';
    await registry.reject(reg.toUpperCase(), reason);
    return _json({'ok': true});
  }

  Future<Response> _adminRevoke(Request req, String reg) async {
    if (!_isAdmin(req)) return _error(401, 'Admin token required.');
    await registry.revoke(reg.toUpperCase());
    return _json({'ok': true});
  }

  // ---- relay ---------------------------------------------------------------

  Future<Response> _deposit(Request req, String mailbox, String grant) async {
    if (!_validMailbox(mailbox)) return _error(400, 'Unknown mailbox.');
    final exp = DateTime.tryParse(req.headers[RelayApi.hExpires] ?? '');
    final now = clock();
    if (exp == null || !exp.isAfter(now)) return _error(400, 'Missing or past expiry.');
    if (exp.difference(now) > RelayApi.maxHold) return _error(400, 'Expiry beyond 48 hours.');
    final body = Uint8List.fromList(await req.read().expand((c) => c).toList());
    if (body.isEmpty || body.length > 5 * 1024 * 1024) return _error(413, 'Share too large.');
    relay.put(mailbox, Uri.decodeComponent(grant), RelayItem(envelope: body, expiresAt: exp, withdrawHash: req.headers[RelayApi.hWithdrawHash]));
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
      if (secret == null || await RelayApi.patientMailboxFor(secret) != mailbox) return _error(403, 'Not your mailbox.');
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
    if (qr == null || time == null || sig == null) return 'Signed request required.';
    if (now.difference(time).abs() > RelayApi.signatureSkew) return 'Request time too far from server time.';
    final DoctorCertificate cert;
    try {
      cert = await (await registry.trust()).verify(qr, now);
    } on CertificateRejected catch (e) {
      return e.patientMessage;
    }
    if (registry.isRevoked(cert.registryId)) return 'Certificate revoked.';
    if (await RelayApi.doctorMailbox(cert.encryptionKey) != mailbox) return 'Mailbox does not belong to this certificate.';
    final ok = await Ed25519().verify(
      RelayApi.pickupMessage(mailbox, time),
      signature: Signature(base64Decode(sig), publicKey: SimplePublicKey(cert.signingKey, type: KeyPairType.ed25519)),
    );
    return ok ? null : 'Bad signature.';
  }

  static bool _validMailbox(String m) => RegExp(r'^(d|p)-[0-9a-f]{16,64}$').hasMatch(m);

  // ---- backup vault --------------------------------------------------------

  static const _maxBackup = 60 * 1024 * 1024;

  /// Same comparison time whatever the input, so a guesser learns nothing
  /// from how long a refusal takes.
  static bool _same(String? a, String? b) {
    if (a == null || b == null || a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  /// Creates a backup, or replaces it when the caller proves the current
  /// password with its verifier.
  Future<Response> _vaultPut(Request req, String account) async {
    if (!VaultStore.validAccount(account)) return _error(400, 'Unknown account format.');
    final existing = await vault.get(account);
    if (existing != null && !_same(req.headers[RelayApi.hVerifier], existing['verifier'] as String?)) {
      return _error(403, 'This backup belongs to someone else, or the password is wrong.');
    }
    final raw = await req.read().expand((c) => c).take(_maxBackup + 1).toList();
    if (raw.length > _maxBackup) return _error(413, 'Backup too large.');
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
      'verifier': b['verifier'],
      'wrappedDataKey': b['wrappedDataKey'],
      'blob': b['blob'],
      'updatedAt': clock().toIso8601String(),
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
    if (vault.lockedOut(account, now)) return _error(429, 'Too many wrong passwords. Try again in an hour.');
    final e = await vault.get(account);
    String? given;
    try {
      given = ((jsonDecode(await req.readAsString()) as Map)['verifier']) as String?;
    } on Object {
      given = null;
    }
    if (e == null || !_same(given, e['verifier'] as String?)) {
      vault.failed(account, now);
      return _error(403, 'Wrong account code or password.');
    }
    vault.succeeded(account);
    return _json({'wrappedDataKey': e['wrappedDataKey'], 'blob': e['blob'], 'updatedAt': e['updatedAt']});
  }

  /// For recovery with two recovery codes: the sealed blob only — no
  /// verifier, no wrapped key.
  Future<Response> _vaultBlob(Request _, String account) async {
    final e = VaultStore.validAccount(account) ? await vault.get(account) : null;
    return e == null ? _error(404, 'No backup for this account code.') : _json({'blob': e['blob'], 'updatedAt': e['updatedAt']});
  }

  Future<Response> _vaultDelete(Request req, String account) async {
    final e = VaultStore.validAccount(account) ? await vault.get(account) : null;
    if (e == null) return _json({'deleted': false});
    if (!_same(req.headers[RelayApi.hVerifier], e['verifier'] as String?)) return _error(403, 'Wrong password.');
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
    final Map<String, Object?> b;
    try {
      b = (jsonDecode(await req.readAsString()) as Map).cast();
    } on Object {
      return _error(400, 'Invalid registration.');
    }
    final id = LifeTrackId.parse('${b['id']}');
    if (id == null || !_validMailbox('${b['mailbox']}') || !'${b['mailbox']}'.startsWith('p-') || !_validKey(b['key']) || b['tokenHash'] is! String) {
      return _error(400, 'Invalid registration.');
    }
    if (ids.contains(id)) return _error(409, 'That ID is taken.');
    await ids.put(id, {'mailbox': b['mailbox'], 'key': b['key'], 'tokenHash': b['tokenHash'], 'createdAt': clock().toIso8601String()});
    return _json({'id': id}, status: 201);
  }

  /// Where to send a request for this person. Public: it names a mailbox
  /// and a key, nothing about who they are.
  Response _idLookup(Request _, String id) {
    final e = LifeTrackId.parse(Uri.decodeComponent(id)) == null ? null : ids[LifeTrackId.parse(Uri.decodeComponent(id))!];
    return e == null ? _error(404, 'No such LifeTrack ID.') : _json({'id': LifeTrackId.parse(Uri.decodeComponent(id)), 'mailbox': e['mailbox'], 'key': e['key']});
  }

  /// A restored phone points its ID at its new mailbox and key.
  Future<Response> _idMove(Request req, String id) async {
    final e = LifeTrackId.parse(Uri.decodeComponent(id)) == null ? null : ids[LifeTrackId.parse(Uri.decodeComponent(id))!];
    if (e == null) return _error(404, 'No such LifeTrack ID.');
    final token = req.headers[RelayApi.hIdToken];
    if (token == null || !_same(await RelayApi.sha256Hex(token), e['tokenHash'] as String?)) return _error(403, 'Not your ID.');
    final Map<String, Object?> b;
    try {
      b = (jsonDecode(await req.readAsString()) as Map).cast();
    } on Object {
      return _error(400, 'Invalid update.');
    }
    if (!_validMailbox('${b['mailbox']}') || !_validKey(b['key'])) return _error(400, 'Invalid update.');
    await ids.put(LifeTrackId.parse(Uri.decodeComponent(id))!, {...e, 'mailbox': b['mailbox'], 'key': b['key']});
    return _json({'ok': true});
  }

  Future<Response> _idDelete(Request req, String id) async {
    final e = LifeTrackId.parse(Uri.decodeComponent(id)) == null ? null : ids[LifeTrackId.parse(Uri.decodeComponent(id))!];
    if (e == null) return _json({'deleted': false});
    final token = req.headers[RelayApi.hIdToken];
    if (token == null || !_same(await RelayApi.sha256Hex(token), e['tokenHash'] as String?)) return _error(403, 'Not your ID.');
    await ids.remove(LifeTrackId.parse(Uri.decodeComponent(id))!);
    return _json({'deleted': true});
  }

  // ---- helpers -------------------------------------------------------------

  static Response _json(Object body, {int status = 200}) =>
      Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json'});

  static Response _error(int status, String message) => _json({'error': message}, status: status);

  /// The doctor web app runs on another localhost port in development.
  static Middleware _cors() => (inner) => (req) async {
        const h = {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'access-control-allow-headers': '*',
        };
        if (req.method == 'OPTIONS') return Response.ok('', headers: h);
        final res = await inner(req);
        return res.change(headers: h);
      };
}
