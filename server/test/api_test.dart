import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime.utc(2026, 9, 30, 12);
  late Handler h;
  late RelayStore relay;
  late Directory vaultDir;
  late SimpleKeyPair enc, sign;
  const admin = 'admin-secret';

  Future<Response> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async => h(Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body is Uint8List ? body : (body == null ? null : jsonEncode(body)),
        headers: headers,
      ));

  Future<Map<String, Object?>> json(Response r) async => (jsonDecode(await r.readAsString()) as Map).cast();

  Future<String> enrolAndApprove() async {
    await call('POST', '/v1/doctors', body: {
      'registrationNo': 'DMC-12345',
      'name': 'Dr. R. Mehta',
      'speciality': 'Cardiology',
      'council': 'Delhi Medical Council',
      'encryptionKey': base64Encode((await enc.extractPublicKey()).bytes),
      'signingKey': base64Encode((await sign.extractPublicKey()).bytes),
    });
    final r = await call('POST', '/v1/admin/doctors/DMC-12345/approve', headers: {RelayApi.hAdmin: admin});
    return (await json(r))['certificate']! as String;
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 30, 12);
    enc = await X25519().newKeyPair();
    sign = await Ed25519().newKeyPair();
    relay = RelayStore();
    final registry = await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair());
    vaultDir = Directory.systemTemp.createTempSync('lt-vault-');
    h = LifeTrackApi(registry: registry, relay: relay, vault: VaultStore(vaultDir), ids: await IdRegistry.open(), adminToken: admin, clock: () => now).handler;
  });

  group('registry', () {
    test('an enrolment is pending until an admin approves it', () async {
      final r = await call('POST', '/v1/doctors', body: {
        'registrationNo': 'dmc-12345',
        'name': 'Dr. R. Mehta',
        'speciality': 'Cardiology',
        'council': 'Delhi Medical Council',
        'encryptionKey': base64Encode((await enc.extractPublicKey()).bytes),
        'signingKey': base64Encode((await sign.extractPublicKey()).bytes),
      });
      expect(r.statusCode, 202);
      final doc = await json(await call('GET', '/v1/doctors/DMC-12345'));
      expect(doc['status'], 'pending');
      expect(doc['note'], contains('manual'));
      expect(doc.containsKey('certificate'), isFalse);
    });

    test('approval needs the admin token and yields a certificate the registry key verifies', () async {
      expect((await call('POST', '/v1/admin/doctors/DMC-1/approve')).statusCode, 401);
      final qr = await enrolAndApprove();
      final key = base64Decode((await json(await call('GET', '/v1/registry/key')))['publicKey']! as String);
      final cert = await RegistryTrust([SimplePublicKey(key, type: KeyPairType.ed25519)]).verify(qr, now);
      expect(cert.name, 'Dr. R. Mehta');
    });

    test('a malformed registration number is refused', () async {
      final r = await call('POST', '/v1/doctors', body: {
        'registrationNo': 'hello',
        'name': 'x',
        'speciality': 'x',
        'council': 'x',
        'encryptionKey': base64Encode(List.filled(32, 1)),
        'signingKey': base64Encode(List.filled(32, 2)),
      });
      expect(r.statusCode, 400);
    });
  });

  group('relay', () {
    Future<Map<String, String>> signed(String qr, String mailbox, {DateTime? at, SimpleKeyPair? key}) =>
        RelayApi.doctorPickupHeaders(certificateQr: qr, signingKey: key ?? sign, mailbox: mailbox, at: at ?? now);

    test('a doctor picks up only its own mailbox, with a fresh signed request, and pickup deletes', () async {
      final qr = await enrolAndApprove();
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      final put = await call('PUT', '/v1/relay/$mailbox/g1',
          body: Uint8List.fromList([1, 2, 3]), headers: {RelayApi.hExpires: now.add(const Duration(hours: 4)).toIso8601String()});
      expect(put.statusCode, 201);

      expect((await call('GET', '/v1/relay/$mailbox')).statusCode, 403, reason: 'unsigned');
      expect((await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox, key: await Ed25519().newKeyPair()))).statusCode, 403,
          reason: 'wrong key');
      expect((await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox, at: now.subtract(const Duration(minutes: 10))))).statusCode,
          403,
          reason: 'stale');

      final ok = await json(await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox)));
      expect((ok['items']! as List).single, containsPair('grantId', 'g1'));
      final again = await json(await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox)));
      expect(again['items'], isEmpty);
    });

    test("a doctor cannot read another doctor's mailbox", () async {
      final qr = await enrolAndApprove();
      final other = 'd-${'0' * 16}';
      expect((await call('GET', '/v1/relay/$other', headers: await signed(qr, other))).statusCode, 403);
    });

    test('a revoked doctor is refused', () async {
      final qr = await enrolAndApprove();
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      await call('POST', '/v1/admin/doctors/DMC-12345/revoke', headers: {RelayApi.hAdmin: admin});
      expect((await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox))).statusCode, 403);
    });

    test('only the depositor can withdraw, with the token it kept', () async {
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      final token = RelayApi.newToken();
      await call('PUT', '/v1/relay/$mailbox/g1', body: Uint8List.fromList([1]), headers: {
        RelayApi.hExpires: now.add(const Duration(hours: 1)).toIso8601String(),
        RelayApi.hWithdrawHash: await RelayApi.sha256Hex(token),
      });
      expect((await json(await call('DELETE', '/v1/relay/$mailbox/g1', headers: {RelayApi.hWithdrawToken: 'guess'})))['withdrawn'], false);
      expect((await json(await call('DELETE', '/v1/relay/$mailbox/g1', headers: {RelayApi.hWithdrawToken: token})))['withdrawn'], true);
      expect(relay.total, 0);
    });

    test('a patient reply mailbox opens only with its secret', () async {
      final (secret, mailbox) = await RelayApi.newPatientMailbox();
      await call('PUT', '/v1/relay/$mailbox/rx1', body: Uint8List.fromList([9]), headers: {RelayApi.hExpires: now.add(const Duration(hours: 1)).toIso8601String()});
      expect((await call('GET', '/v1/relay/$mailbox')).statusCode, 403);
      expect((await call('GET', '/v1/relay/$mailbox', headers: {RelayApi.hMailboxSecret: 'wrong'})).statusCode, 403);
      final ok = await json(await call('GET', '/v1/relay/$mailbox', headers: {RelayApi.hMailboxSecret: secret}));
      expect((ok['items']! as List), hasLength(1));
    });

    test('nothing is held past its expiry or beyond 48 hours', () async {
      final mailbox = 'd-${'a' * 16}';
      expect((await call('PUT', '/v1/relay/$mailbox/g1', body: Uint8List.fromList([1]), headers: {RelayApi.hExpires: now.add(const Duration(hours: 49)).toIso8601String()})).statusCode, 400);
      await call('PUT', '/v1/relay/$mailbox/g2', body: Uint8List.fromList([1]), headers: {RelayApi.hExpires: now.add(const Duration(hours: 1)).toIso8601String()});
      expect(relay.purgeExpired(now.add(const Duration(hours: 2))), 1);
      expect(relay.total, 0);
    });
  });

  group('backup vault', () {
    const acct = 'LT-7KQM2-XPA9D';
    final entry = {
      'salt': base64Encode(List.filled(16, 1)),
      'verifier': base64Encode(List.filled(32, 2)),
      'wrappedDataKey': base64Encode(List.filled(60, 3)),
      'blob': base64Encode(List.filled(100, 4)),
    };

    test('stores a backup on disk and gives the salt to anyone, the key only to the password', () async {
      expect((await call('PUT', '/v1/vault/$acct', body: entry)).statusCode, 201);
      expect(File('${vaultDir.path}/$acct.json').existsSync(), isTrue);
      expect((await json(await call('GET', '/v1/vault/$acct/salt')))['salt'], entry['salt']);
      expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': base64Encode(List.filled(32, 9))})).statusCode, 403);
      final ok = await json(await call('POST', '/v1/vault/$acct/open', body: {'verifier': entry['verifier']}));
      expect(ok['blob'], entry['blob']);
      expect(ok.containsKey('verifier'), isFalse);
    });

    test('recovery-code path gets the sealed blob only', () async {
      await call('PUT', '/v1/vault/$acct', body: entry);
      final b = await json(await call('GET', '/v1/vault/$acct/blob'));
      expect(b.keys.toSet(), {'blob', 'updatedAt'});
    });

    test('only the password holder can replace or delete a backup', () async {
      await call('PUT', '/v1/vault/$acct', body: entry);
      expect((await call('PUT', '/v1/vault/$acct', body: entry)).statusCode, 403);
      expect((await call('PUT', '/v1/vault/$acct', body: entry, headers: {RelayApi.hVerifier: entry['verifier']!})).statusCode, 200);
      expect((await call('DELETE', '/v1/vault/$acct')).statusCode, 403);
      expect((await json(await call('DELETE', '/v1/vault/$acct', headers: {RelayApi.hVerifier: entry['verifier']!})))['deleted'], true);
      expect((await call('GET', '/v1/vault/$acct/salt')).statusCode, 404);
    });

    test('ten wrong passwords lock the account for an hour', () async {
      await call('PUT', '/v1/vault/$acct', body: entry);
      for (var i = 0; i < 10; i++) {
        expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': 'x'})).statusCode, 403);
      }
      expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': entry['verifier']})).statusCode, 429);
      now = now.add(const Duration(hours: 1, minutes: 1));
      expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': entry['verifier']})).statusCode, 200);
    });

    test('account codes are checked for shape', () async {
      expect((await call('PUT', '/v1/vault/../etc', body: entry)).statusCode, isNot(201));
      expect((await call('PUT', '/v1/vault/lt-abc', body: entry)).statusCode, 400);
    });
  });

  group('LifeTrack IDs', () {
    final key = base64Encode(List.filled(32, 5));
    Future<(String, String)> register() async {
      final id = LifeTrackId.generate();
      const token = 'owner-token';
      final r = await call('POST', '/v1/ids', body: {'id': id, 'mailbox': 'p-${'a' * 64}', 'key': key, 'tokenHash': await RelayApi.sha256Hex(token)});
      expect(r.statusCode, 201);
      return (id, token);
    }

    test('registered once, found by anyone, and reveals only where to send', () async {
      final (id, _) = await register();
      final r = await json(await call('GET', '/v1/ids/${LifeTrackId.display(id)}'));
      expect(r.keys.toSet(), {'id', 'mailbox', 'key'});
      expect((await call('POST', '/v1/ids', body: {'id': id, 'mailbox': 'p-${'b' * 64}', 'key': key, 'tokenHash': 'f' * 64})).statusCode, 409);
    });

    test('a mistyped ID is refused before any lookup', () async {
      final (id, _) = await register();
      final wrong = id.replaceRange(5, 6, id[5] == '0' ? '1' : '0');
      expect((await call('GET', '/v1/ids/$wrong')).statusCode, 404);
      expect((await call('POST', '/v1/ids', body: {'id': '234567890123', 'mailbox': 'p-${'a' * 64}', 'key': key, 'tokenHash': 'f' * 64})).statusCode, 400);
    });

    test('only the owning phone can move or delete it', () async {
      final (id, token) = await register();
      final move = {'mailbox': 'p-${'c' * 64}', 'key': key};
      expect((await call('PUT', '/v1/ids/$id', body: move)).statusCode, 403);
      expect((await call('PUT', '/v1/ids/$id', body: move, headers: {RelayApi.hIdToken: 'nope'})).statusCode, 403);
      expect((await call('PUT', '/v1/ids/$id', body: move, headers: {RelayApi.hIdToken: token})).statusCode, 200);
      expect((await json(await call('GET', '/v1/ids/$id')))['mailbox'], 'p-${'c' * 64}');
      expect((await call('DELETE', '/v1/ids/$id')).statusCode, 403);
      expect((await json(await call('DELETE', '/v1/ids/$id', headers: {RelayApi.hIdToken: token})))['deleted'], true);
      expect((await call('GET', '/v1/ids/$id')).statusCode, 404);
    });
  });

  group('hardening', () {
    Future<Response> enrol(SimpleKeyPair e, SimpleKeyPair s) async => call('POST', '/v1/doctors', body: {
          'registrationNo': 'DMC-12345',
          'name': 'Dr. R. Mehta',
          'speciality': 'Cardiology',
          'council': 'Delhi Medical Council',
          'encryptionKey': base64Encode((await e.extractPublicKey()).bytes),
          'signingKey': base64Encode((await s.extractPublicKey()).bytes),
        });
    Future<Map<String, String>> signed(String qr, String mailbox, {SimpleKeyPair? key}) =>
        RelayApi.doctorPickupHeaders(certificateQr: qr, signingKey: key ?? sign, mailbox: mailbox, at: now);
    Map<String, String> expires() => {RelayApi.hExpires: now.add(const Duration(hours: 1)).toIso8601String()};
    Future<Handler> fresh({RelayStore? relayStore, bool trustProxy = false}) async => LifeTrackApi(
          registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
          relay: relayStore ?? RelayStore(),
          vault: VaultStore(vaultDir),
          ids: await IdRegistry.open(),
          adminToken: admin,
          clock: () => now,
          trustProxy: trustProxy,
        ).handler;

    test('keys waiting for review cannot be swapped by a second enrolment', () async {
      expect((await enrol(enc, sign)).statusCode, 202);
      final first = (await json(await call('GET', '/v1/doctors/DMC-12345')))['keyId'];
      final r = await enrol(await X25519().newKeyPair(), await Ed25519().newKeyPair());
      expect(r.statusCode, 409);
      expect((await json(await call('GET', '/v1/doctors/DMC-12345')))['keyId'], first);
    });

    test('after a revocation, re-enrolling the same number never revives the old certificate', () async {
      final oldQr = await enrolAndApprove();
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      await call('POST', '/v1/admin/doctors/DMC-12345/revoke', headers: {RelayApi.hAdmin: admin});
      // Someone enrols the number again with other keys — pending, then approved.
      expect((await enrol(await X25519().newKeyPair(), await Ed25519().newKeyPair())).statusCode, 202);
      expect((await call('GET', '/v1/relay/$mailbox', headers: await signed(oldQr, mailbox))).statusCode, 403, reason: 'pending re-enrolment');
      await call('POST', '/v1/admin/doctors/DMC-12345/approve', headers: {RelayApi.hAdmin: admin});
      expect((await call('GET', '/v1/relay/$mailbox', headers: await signed(oldQr, mailbox))).statusCode, 403, reason: 'other keys approved');
    });

    test('certificates are short-lived and renewed when the doctor asks', () async {
      final qr = await enrolAndApprove();
      final c = DoctorCertificate.decode(qr);
      expect(c.expiresAt.difference(c.issuedAt), DoctorRegistry.certificateLifetime);
      expect(DoctorRegistry.certificateLifetime, lessThanOrEqualTo(const Duration(days: 30)));
      expect((await json(await call('GET', '/v1/doctors/DMC-12345')))['certificate'], qr, reason: 'not near expiry yet');
      now = now.add(const Duration(days: 25));
      final renewed = DoctorCertificate.decode((await json(await call('GET', '/v1/doctors/DMC-12345')))['certificate']! as String);
      expect(renewed.expiresAt, now.add(DoctorRegistry.certificateLifetime));
      expect(renewed.encryptionKey, c.encryptionKey);
    });

    test('a signed pickup cannot be replayed', () async {
      final qr = await enrolAndApprove();
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      final h0 = await signed(qr, mailbox);
      expect((await call('GET', '/v1/relay/$mailbox', headers: h0)).statusCode, 200);
      await call('PUT', '/v1/relay/$mailbox/g1', body: Uint8List.fromList([1]), headers: expires());
      expect((await call('GET', '/v1/relay/$mailbox', headers: h0)).statusCode, 403);
      expect(relay.countIn(mailbox), 1, reason: 'the replay took nothing');
      final noNonce = {...h0}..remove(RelayApi.hNonce);
      expect((await call('GET', '/v1/relay/$mailbox', headers: noNonce)).statusCode, 403);
    });

    test('a deposit never replaces one already waiting under the same id', () async {
      final qr = await enrolAndApprove();
      final mailbox = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      await call('PUT', '/v1/relay/$mailbox/g1', body: Uint8List.fromList([1]), headers: expires());
      await call('PUT', '/v1/relay/$mailbox/g1', body: Uint8List.fromList([2]), headers: expires());
      final items = (await json(await call('GET', '/v1/relay/$mailbox', headers: await signed(qr, mailbox))))['items']! as List;
      expect([for (final i in items) base64Decode((i as Map)['envelope']! as String).single], [1, 2]);
    });

    test('a full mailbox refuses more instead of growing without end', () async {
      final api = await fresh(relayStore: RelayStore(maxItemsPerMailbox: 2));
      Future<int> put(String g) async =>
          (await api(Request('PUT', Uri.parse('http://localhost/v1/relay/d-${'a' * 16}/$g'), body: Uint8List.fromList([1]), headers: expires()))).statusCode;
      expect([await put('a'), await put('b'), await put('c')], [201, 201, 507]);
    });

    test('wrong proofs on replace and delete count towards the lockout, and the server keeps only a hash', () async {
      const acct = 'LT-7KQM2-XPA9D';
      final verifier = base64Encode(List.filled(32, 2));
      final entry = {'salt': base64Encode(List.filled(16, 1)), 'verifier': verifier, 'wrappedDataKey': base64Encode(List.filled(60, 3)), 'blob': base64Encode(List.filled(100, 4))};
      await call('PUT', '/v1/vault/$acct', body: entry);
      expect(File('${vaultDir.path}/$acct.json').readAsStringSync(), isNot(contains(verifier)));
      for (var i = 0; i < 5; i++) {
        expect((await call('PUT', '/v1/vault/$acct', body: entry, headers: {RelayApi.hVerifier: 'guess$i'})).statusCode, 403);
        expect((await call('DELETE', '/v1/vault/$acct', headers: {RelayApi.hVerifier: 'guess$i'})).statusCode, 403);
      }
      expect((await call('DELETE', '/v1/vault/$acct', headers: {RelayApi.hVerifier: verifier})).statusCode, 429);
      // The count survives a restart.
      final restarted = await fresh();
      final r = await restarted(Request('POST', Uri.parse('http://localhost/v1/vault/$acct/open'), body: jsonEncode({'verifier': verifier})));
      expect(r.statusCode, 429);
    });

    test('a backup stored before hashing still opens, and is rewritten hashed', () async {
      const acct = 'LT-7KQM2-XPA9E';
      final verifier = base64Encode(List.filled(32, 2));
      File('${vaultDir.path}/$acct.json')
          .writeAsStringSync(jsonEncode({'salt': 'AA==', 'verifier': verifier, 'wrappedDataKey': 'AA==', 'blob': 'AA==', 'updatedAt': now.toIso8601String()}));
      expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': verifier})).statusCode, 200);
      final stored = File('${vaultDir.path}/$acct.json').readAsStringSync();
      expect(stored, isNot(contains(verifier)));
      expect(stored, contains('verifierHash'));
      expect((await call('POST', '/v1/vault/$acct/open', body: {'verifier': verifier})).statusCode, 200);
    });

    test('web pages on other sites, and rebinding host names, are refused', () async {
      expect((await call('GET', '/v1/health', headers: {'origin': 'https://evil.example'})).statusCode, 403);
      final ok = await call('GET', '/v1/health', headers: {'origin': 'http://localhost:5173'});
      expect(ok.statusCode, 200);
      expect(ok.headers['access-control-allow-origin'], 'http://localhost:5173');
      expect((await call('GET', '/v1/health')).headers.containsKey('access-control-allow-origin'), isFalse);
      expect((await h(Request('GET', Uri.parse('http://evil.example:8787/v1/health')))).statusCode, 421);
    });

    test('the admin token is required on every admin route, and a bad reject body is not a crash', () async {
      await enrol(enc, sign);
      expect((await call('POST', '/v1/admin/doctors/DMC-12345/reject', body: {'reason': 'x'}, headers: {RelayApi.hAdmin: 'admin-secreT'})).statusCode, 401);
      final r = await h(Request('POST', Uri.parse('http://localhost/v1/admin/doctors/DMC-12345/reject'), body: 'not json', headers: {RelayApi.hAdmin: admin}));
      expect(r.statusCode, 200);
      expect((await call('POST', '/v1/admin/doctors/NOPE-1/revoke', headers: {RelayApi.hAdmin: admin})).statusCode, 404);
    });

    test('ID lookups are rate-limited, so the number space cannot be walked', () async {
      final codes = <int>[];
      for (var i = 0; i < 61; i++) {
        codes.add((await call('GET', '/v1/ids/${LifeTrackId.generate()}')).statusCode);
      }
      expect(codes.take(60).toSet(), {404});
      expect(codes.last, 429);
      now = now.add(const Duration(minutes: 1));
      expect((await call('GET', '/v1/ids/${LifeTrackId.generate()}')).statusCode, 404);
    });

    test('oversized bodies are refused before they are read whole', () async {
      expect((await call('POST', '/v1/ids', body: {'id': 'x' * (LifeTrackApi.maxJson + 1)})).statusCode, 400);
      expect((await call('PUT', '/v1/relay/d-${'a' * 16}/g', body: Uint8List(LifeTrackApi.maxShare + 1), headers: expires())).statusCode, 413);
    });

    test('behind a trusted proxy, each caller has its own budget and cannot pick its address', () async {
      final api = await fresh(trustProxy: true);
      Future<int> lookup(String forwarded) async =>
          (await api(Request('GET', Uri.parse('http://localhost/v1/ids/${LifeTrackId.generate()}'), headers: {'x-forwarded-for': forwarded}))).statusCode;
      for (var i = 0; i < 60; i++) {
        expect(await lookup('203.0.113.7'), 404);
      }
      expect(await lookup('203.0.113.7'), 429);
      // A spoofed first entry does not help: the proxy appends the real one.
      expect(await lookup('198.51.100.1, 203.0.113.7'), 429);
      expect(await lookup('203.0.113.8'), 404, reason: 'another phone is not held back by the first');

      // Without --trust-proxy the header is ignored: everyone is one client.
      final plain = await fresh();
      for (var i = 0; i < 60; i++) {
        await plain(Request('GET', Uri.parse('http://localhost/v1/ids/${LifeTrackId.generate()}'), headers: {'x-forwarded-for': '10.0.0.$i'}));
      }
      expect((await plain(Request('GET', Uri.parse('http://localhost/v1/ids/${LifeTrackId.generate()}'), headers: {'x-forwarded-for': '10.0.0.99'}))).statusCode, 429);
    });

    test('guessing backup account codes is throttled and writes nothing to disk', () async {
      final api = await fresh();
      final codes = <int>[];
      for (var i = 0; i < 21; i++) {
        final acct = 'LT-GUESS-${i.toString().padLeft(5, '0')}';
        codes.add((await api(Request('POST', Uri.parse('http://localhost/v1/vault/$acct/open'), body: jsonEncode({'verifier': 'x'})))).statusCode);
      }
      expect(codes.take(20).toSet(), {403});
      expect(codes.last, 429);
      expect(File('${vaultDir.path}/_failures.json').existsSync(), isFalse);
    });
  });
}
