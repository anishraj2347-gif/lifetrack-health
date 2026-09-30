import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shelf/shelf.dart' as shelf;

/// The patient app and a doctor, both over the real HTTP contract: the doctor
/// knows only the patient's 12-digit LifeTrack ID.
void main() {
  test('doctor asks by LifeTrack ID; patient approves; doctor receives; a second ask is declined', () async {
    final now = DateTime.now().toUtc();
    const admin = 'admin';
    final handler = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-vault-')),
      ids: await IdRegistry.open(),
      adminToken: admin,
    ).handler;
    final client = MockClient((req) async {
      final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
      return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
    });
    final base = Uri.parse('http://127.0.0.1:8787');

    // A verified doctor.
    final enc = await X25519().newKeyPair();
    final sign = await Ed25519().newKeyPair();
    await client.post(base.resolve('/v1/doctors'), body: jsonEncode({
      'registrationNo': 'DMC-12345', 'name': 'Dr. R. Mehta', 'speciality': 'Cardiology', 'council': 'Delhi Medical Council',
      'encryptionKey': base64Encode((await enc.extractPublicKey()).bytes), 'signingKey': base64Encode((await sign.extractPublicKey()).bytes),
    }));
    await client.post(base.resolve('/v1/admin/doctors/DMC-12345/approve'), headers: {RelayApi.hAdmin: admin});
    final qr = (jsonDecode((await client.get(base.resolve('/v1/doctors/DMC-12345'))).body) as Map)['certificate']! as String;
    final registryKey = (jsonDecode((await client.get(base.resolve('/v1/registry/key'))).body) as Map)['publicKey']! as String;

    // The patient's phone.
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 1)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => DateTime.now().toUtc(),
      share: ShareConfig(relayUrl: '$base', registryKey: registryKey),
      relayOverride: (t) => HttpRelayClient(baseUrl: base, tokens: t, client: client),
      idDirectoryOverride: () => HttpIdDirectory(baseUrl: base, client: client),
    );
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female, demo: true);
    final id = s.lifeTrackIdOf(s.selfPatientId!)!;

    // The doctor, knowing only the ID.
    Future<String> ask(List<String> levels) async {
      final look = jsonDecode((await client.get(base.resolve('/v1/ids/${LifeTrackId.display(id)}'))).body) as Map;
      final key = base64Decode(look['key']! as String);
      final r = await AccessRequest(
        requestId: 'req-${DateTime.now().microsecondsSinceEpoch}', lifeTrackId: id, levels: levels,
        issuedAt: now, expiresAt: now.add(const Duration(hours: 24)), certificate: qr,
      ).signedWith(sign);
      final put = await client.put(
        base.resolve(RelayApi.itemPath(look['mailbox']! as String, r.requestId)),
        body: await ShareEnvelope.seal(bundle: r.toJson(), recipientKey: key, keyId: await RelayApi.keyId(key), grantId: r.requestId, expiresAt: r.expiresAt),
        headers: {RelayApi.hExpires: r.expiresAt.toIso8601String()},
      );
      expect(put.statusCode, 201);
      return r.requestId;
    }

    Future<List<Map<String, Object?>>> doctorPickUp() async {
      final mb = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
      final r = await client.get(base.resolve(RelayApi.mailboxPath(mb)),
          headers: await RelayApi.doctorPickupHeaders(certificateQr: qr, signingKey: sign, mailbox: mb, at: DateTime.now().toUtc()));
      return [
        for (final i in (jsonDecode(r.body) as Map)['items'] as List)
          await ShareEnvelope.open(base64Decode((i as Map)['envelope']! as String), enc, DateTime.now().toUtc()),
      ];
    }

    await ask(['summary']);
    await s.checkInbox();
    final p = (await s.pendingRequests()).single;
    expect(await doctorPickUp(), isEmpty, reason: 'nothing before the patient approves');
    await s.sharing!.share(patientId: s.selfPatientId!, doctor: p.doctor, levels: p.levels, requested: p.levels, at: DateTime.now().toUtc(), grantorId: s.actingGrantor());
    await s.requests!.remove(p.request.requestId);
    final got = await doctorPickUp();
    expect((got.single['patient'] as Map)['name'], 'Anjali Sharma');
    expect(got.single['levels'], [AccessLevel.summary.name]);

    final second = await ask(['allReports']);
    await s.checkInbox();
    await s.declineRequest((await s.pendingRequests()).single);
    expect(await doctorPickUp(), [{'type': 'declined', 'requestId': second}]);
  });
}
