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

/// A demonstration build's made-up people get LifeTrack IDs only from a
/// server in practice mode, and are recorded as samples.
void main() {
  Future<(Handler, IdRegistry)> server({required bool allowSamples}) async {
    final ids = await IdRegistry.open();
    final h = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-v-')),
      ids: ids,
      adminToken: 'a',
      requireIdentity: true,
      allowSampleIds: allowSamples,
    ).handler;
    return (h, ids);
  }

  Future<Response> register(Handler h, {required bool sample}) => Future.value(h(Request('POST', Uri.parse('http://127.0.0.1:8787/v1/ids'),
      body: jsonEncode({'id': LifeTrackId.generate(), 'mailbox': 'p-${'a' * 64}', 'key': base64Encode(List.filled(32, 5)), 'tokenHash': 'f' * 64, if (sample) 'sample': true}))));

  test('practice mode: a sample person gets an ID, marked as a sample', () async {
    final (h, ids) = await server(allowSamples: true);
    final r = await register(h, sample: true);
    expect(r.statusCode, 201);
    final id = (jsonDecode(await r.readAsString()) as Map)['id'] as String;
    expect(ids[id]!['sample'], isTrue);
    expect(ids[id]!['subject'], isNull);
    expect((await register(h, sample: false)).statusCode, 400, reason: 'a real person still needs an identity check');
  });

  test('without practice mode, "sample" opens nothing', () async {
    final (h, _) = await server(allowSamples: false);
    expect((await register(h, sample: true)).statusCode, 400);
  });
}
