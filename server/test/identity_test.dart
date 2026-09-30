import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/identity.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime(2026, 10, 1, 10);
  late Handler h;
  late RegistryTrust trust;

  Future<Response> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async => h(Request(
        method,
        Uri.parse('http://127.0.0.1:8787$path'),
        body: body == null ? null : jsonEncode(body),
        headers: headers,
      ));
  Future<Map<String, Object?>> json(Response r) async => (jsonDecode(await r.readAsString()) as Map).cast();

  setUp(() async {
    now = DateTime(2026, 10, 1, 10);
    final key = await Ed25519().newKeyPair();
    trust = RegistryTrust([await key.extractPublicKey()]);
    final registry = await DoctorRegistry.open(signingKey: key);
    h = LifeTrackApi(
      registry: registry,
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-v-')),
      ids: await IdRegistry.open(),
      adminToken: 'a',
      identity: IdentityService(provider: PracticeDigiLocker(), registryKey: key, hmacSecret: List.filled(32, 7), trust: trust, clock: () => now),
      requireIdentity: true,
      clock: () => now,
    ).handler;
  });

  /// The whole browser round trip: start → DigiLocker page → consent →
  /// callback → the app collects the signed result.
  Future<Map<String, Object?>> verify(String account, {String purpose = 'self', IdentityAttestation? parent}) async {
    final start = await json(await call('POST', '/v1/verify/start', body: {'purpose': purpose, if (parent != null) 'parent': parent.toJson()}));
    if (start['error'] != null) return {'status': 'refused', 'error': start['error']};
    final auth = Uri.parse(start['authorizeUrl']! as String);
    final page = await (await call('GET', auth.toString().replaceFirst('http://127.0.0.1:8787', ''))).readAsString();
    expect(page, contains('Practice DigiLocker'));
    final approve = await call('GET', '/v1/practice-digilocker/approve?state=${auth.queryParameters['state']}&challenge=${Uri.encodeQueryComponent(auth.queryParameters['challenge']!)}&account=$account');
    expect(approve.statusCode, 302);
    final cb = Uri.parse(approve.headers['location']!);
    await call('GET', '${cb.path}?${cb.query}');
    expect((await json(await call('GET', '/v1/verify/${start['session']}', headers: {RelayApi.hSessionSecret: 'wrong'})))['status'], 'expired');
    return json(await call('GET', '/v1/verify/${start['session']}', headers: {RelayApi.hSessionSecret: start['secret']! as String}));
  }

  test('an Aadhaar-linked DigiLocker account gives a signed identity, with no ID number in it', () async {
    final r = await verify('anjali');
    expect(r['status'], 'done');
    final a = IdentityAttestation.fromJson((r['attestation']! as Map).cast());
    expect((a.name, a.dateOfBirth, a.gender, a.method), ('Anjali Sharma', DateTime(1984, 6, 14), 'F', IdentityMethod.aadhaarDigiLocker));
    expect(await a.verifies(trust), isTrue);
    expect(jsonEncode(r), isNot(contains('practice-anjali')), reason: 'the DigiLocker id never leaves the server');
  });

  test('an account without Aadhaar is refused', () async {
    final r = await verify('noaadhaar');
    expect(r['status'], 'error');
    expect(r['error'], contains('not linked to an Aadhaar'));
  });

  test("a newborn: only from the verified parent's own DigiLocker, only under one year", () async {
    final mum = IdentityAttestation.fromJson(((await verify('anjali'))['attestation']! as Map).cast());
    expect((await verify('anjali', purpose: 'newborn'))['status'], 'refused', reason: 'no parent given');
    final baby = await verify('anjali', purpose: 'newborn', parent: mum);
    final b = IdentityAttestation.fromJson((baby['attestation']! as Map).cast());
    expect((b.method, b.name, b.parentSubjectHash), (IdentityMethod.birthCertificateDigiLocker, 'Baby of Anjali Sharma', mum.subjectHash));
    expect((await verify('vikram', purpose: 'newborn', parent: mum))['error'], contains('as the parent'));
    now = DateTime(2027, 9, 1);
    expect((await verify('anjali', purpose: 'newborn', parent: mum))['error'], contains('over one year'));
  });

  test('one person, one LifeTrack ID', () async {
    final a = ((await verify('anjali'))['attestation']! as Map).cast<String, Object?>();
    final key = base64Encode(List.filled(32, 5));
    Future<Response> reg(Map<String, Object?>? att) => call('POST', '/v1/ids', body: {
          'id': LifeTrackId.generate(), 'mailbox': 'p-${'a' * 64}', 'key': key, 'tokenHash': 'x', if (att != null) 'attestation': att,
        });
    expect((await reg(null)).statusCode, 400, reason: 'identity required');
    expect((await reg(a)).statusCode, 201);
    final again = await reg(((await verify('anjali'))['attestation']! as Map).cast());
    expect(again.statusCode, 409);
    expect((await json(again))['reason'], 'person_exists');
    expect((await reg({...a, 'name': 'Someone Else'})).statusCode, 400, reason: 'altered attestation');
  });
}
