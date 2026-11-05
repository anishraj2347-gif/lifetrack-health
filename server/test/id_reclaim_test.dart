import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A verified person who lost their token gets their own ID back, and nobody
/// else gets it.
void main() {
  var now = DateTime.utc(2026, 11, 6, 12);
  late Handler h;
  late SimpleKeyPair registryKey;
  final key = base64Encode(List.filled(32, 5));
  final oldBox = 'p-${'a' * 64}';
  final newBox = 'p-${'b' * 64}';

  Future<Response> call(String method, String path, {Object? body, Map<String, String> headers = const {}}) async =>
      h(Request(method, Uri.parse('http://localhost$path'), body: body == null ? null : jsonEncode(body), headers: headers));

  Future<Map<String, Object?>> json(Response r) async => (jsonDecode(await r.readAsString()) as Map).cast();

  Future<IdentityAttestation> check(String subject, {DateTime? at, SimpleKeyPair? signer}) => IdentityAttestation(
        method: IdentityMethod.aadhaarDigiLocker,
        name: 'Anjali Sharma',
        dateOfBirth: DateTime(1984, 6, 14),
        gender: 'F',
        subjectHash: subject,
        verifiedAt: at ?? now,
      ).signedWith(signer ?? registryKey);

  Future<String> register(String subject) async {
    final a = await check(subject);
    now = now.add(const Duration(seconds: 5));
    final id = LifeTrackId.generate();
    final r = await call('POST', '/v1/ids', body: {'id': id, 'mailbox': oldBox, 'key': key, 'tokenHash': await RelayApi.sha256Hex('old-token'), 'attestation': a.toJson()});
    expect(r.statusCode, 201);
    return id;
  }

  Future<Response> reclaim(IdentityAttestation a, {String token = 'new-token', Map<String, Object?> extra = const {}}) async =>
      call('POST', '/v1/ids/reclaim', body: {'mailbox': newBox, 'key': key, 'tokenHash': await RelayApi.sha256Hex(token), 'attestation': a.toJson(), ...extra});

  Future<String?> mailboxOf(String id) async => (await json(await call('GET', '/v1/ids/$id')))['mailbox'] as String?;

  setUp(() async {
    now = DateTime.utc(2026, 11, 6, 12);
    registryKey = await Ed25519().newKeyPair();
    h = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: registryKey),
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-reclaim-')),
      ids: await IdRegistry.open(),
      adminToken: 'a',
      clock: () => now,
    ).handler;
  });

  test('a fresh check moves the same ID to the new phone under a new token', () async {
    final id = await register('subject-anjali');
    now = now.add(const Duration(days: 30));
    final r = await reclaim(await check('subject-anjali'));
    expect(r.statusCode, 200);
    expect((await json(r))['id'], id);
    expect(await mailboxOf(id), newBox);

    expect((await call('DELETE', '/v1/ids/$id', headers: {RelayApi.hIdToken: 'old-token'})).statusCode, 403, reason: 'the old token is finished');
    expect((await call('DELETE', '/v1/ids/$id', headers: {RelayApi.hIdToken: 'new-token'})).statusCode, 200);
  });

  test("someone else's check cannot reach this ID, even naming it", () async {
    final id = await register('subject-anjali');
    await register('subject-vikram');
    now = now.add(const Duration(minutes: 1));
    final r = await reclaim(await check('subject-vikram'), extra: {'id': id});
    expect(r.statusCode, 200);
    expect((await json(r))['id'], isNot(id));
    expect(await mailboxOf(id), oldBox);
  });

  test('a person with no ID gets nothing', () async {
    final id = await register('subject-anjali');
    expect((await reclaim(await check('subject-stranger'))).statusCode, 404);
    expect(await mailboxOf(id), oldBox);
  });

  test('a check not signed by this registry is refused', () async {
    final id = await register('subject-anjali');
    final forged = await check('subject-anjali', signer: await Ed25519().newKeyPair());
    expect((await reclaim(forged)).statusCode, 400);
    expect(await mailboxOf(id), oldBox);
  });

  test('details changed after signing are refused', () async {
    final id = await register('subject-anjali');
    final j = (await check('subject-anjali')).toJson();
    final tampered = IdentityAttestation.fromJson({...j, 'verifiedAt': now.add(const Duration(minutes: 1)).toIso8601String()});
    expect((await reclaim(tampered)).statusCode, 400);
    expect(await mailboxOf(id), oldBox);
  });

  test('the check that made the ID cannot move it, however recent', () async {
    final a = await check('subject-anjali');
    now = now.add(const Duration(seconds: 5));
    final id = LifeTrackId.generate();
    await call('POST', '/v1/ids', body: {'id': id, 'mailbox': oldBox, 'key': key, 'tokenHash': await RelayApi.sha256Hex('old-token'), 'attestation': a.toJson()});
    final r = await reclaim(a);
    expect(r.statusCode, 403);
    expect((await json(r))['reason'], 'stale_check');
    expect(await mailboxOf(id), oldBox);
  });

  test('one check moves an ID once', () async {
    final id = await register('subject-anjali');
    now = now.add(const Duration(minutes: 1));
    final a = await check('subject-anjali');
    now = now.add(const Duration(seconds: 5));
    expect((await reclaim(a)).statusCode, 200);
    now = now.add(const Duration(seconds: 5));
    final again = await reclaim(a, token: 'thief');
    expect(again.statusCode, 403, reason: 'a copy of it cannot take the ID back');
    expect((await call('DELETE', '/v1/ids/$id', headers: {RelayApi.hIdToken: 'thief'})).statusCode, 403);
  });

  test('a check older than the window, or dated ahead, is refused', () async {
    final id = await register('subject-anjali');
    now = now.add(const Duration(days: 1));
    final old = await check('subject-anjali', at: now.subtract(LifeTrackApi.reclaimWindow + const Duration(seconds: 1)));
    expect((await reclaim(old)).statusCode, 403);
    final ahead = await check('subject-anjali', at: now.add(const Duration(hours: 1)));
    expect((await reclaim(ahead)).statusCode, 403);
    expect(await mailboxOf(id), oldBox);
    final justInTime = await check('subject-anjali', at: now.subtract(LifeTrackApi.reclaimWindow - const Duration(seconds: 1)));
    expect((await reclaim(justInTime)).statusCode, 200);
  });

  test('a bad request changes nothing', () async {
    final a = await check('subject-anjali');
    final hash = await RelayApi.sha256Hex('t');
    for (final body in [
      {'mailbox': newBox, 'key': key, 'tokenHash': hash},
      {'mailbox': 'd-${'b' * 64}', 'key': key, 'tokenHash': hash, 'attestation': a.toJson()},
      {'mailbox': newBox, 'key': 'short', 'tokenHash': hash, 'attestation': a.toJson()},
      {'mailbox': newBox, 'key': key, 'tokenHash': 'nothex', 'attestation': a.toJson()},
      {'mailbox': newBox, 'key': key, 'tokenHash': hash, 'attestation': {'method': 'nonsense'}},
    ]) {
      expect((await call('POST', '/v1/ids/reclaim', body: body)).statusCode, 400);
    }
  });

  test('it is rate limited', () async {
    final codes = <int>[];
    for (var i = 0; i < 12; i++) {
      codes.add((await reclaim(await check('subject-nobody'))).statusCode);
    }
    expect(codes.first, 404);
    expect(codes.last, 429);
  });
}
