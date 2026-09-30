import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'registry.dart';
import 'relay_store.dart';

/// HTTP routes. Every response is JSON; no response ever contains a
/// decrypted record, because the server never holds a key that makes one.
class LifeTrackApi {
  LifeTrackApi({required this.registry, required this.relay, required this.adminToken, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final DoctorRegistry registry;
  final RelayStore relay;
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
      ..get('/v1/relay/<mailbox>', _pickup);
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
