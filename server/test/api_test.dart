import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
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
    h = LifeTrackApi(registry: registry, relay: relay, vault: VaultStore(vaultDir), adminToken: admin, clock: () => now).handler;
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
}
