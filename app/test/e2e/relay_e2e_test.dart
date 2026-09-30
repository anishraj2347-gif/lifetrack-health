import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_store.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/consent/record_access.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/share/clinical_share_service.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/share/reply_identity.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/record_repository.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:shelf/shelf.dart' as shelf;

/// The patient app's real HTTP client against the real server handler,
/// joined in memory: the whole phase 2 path, byte for byte, with no socket.
void main() {
  test('enrol, approve, share, pick up, prescribe, collect — over the real HTTP contract', () async {
    final now = DateTime.now().toUtc();
    const admin = 'admin';
    final registry = await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair());
    final relayStore = RelayStore();
    final handler = LifeTrackApi(registry: registry, relay: relayStore, adminToken: admin).handler;
    final client = MockClient((req) async {
      final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
      return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
    });
    final base = Uri.parse('http://127.0.0.1:8787');

    // Doctor enrols from a browser; an admin approves after a licence check.
    final enc = await X25519().newKeyPair();
    final sign = await Ed25519().newKeyPair();
    final enrol = await client.post(base.resolve('/v1/doctors'), body: jsonEncode({
      'registrationNo': 'DMC-12345',
      'name': 'Dr. R. Mehta',
      'speciality': 'Cardiology',
      'council': 'Delhi Medical Council',
      'encryptionKey': base64Encode((await enc.extractPublicKey()).bytes),
      'signingKey': base64Encode((await sign.extractPublicKey()).bytes),
    }));
    expect(enrol.statusCode, 202);
    await client.post(base.resolve('/v1/admin/doctors/DMC-12345/approve'), headers: {RelayApi.hAdmin: admin});
    final qr = (jsonDecode((await client.get(base.resolve('/v1/doctors/DMC-12345'))).body) as Map)['certificate']! as String;
    final registryKey = (jsonDecode((await client.get(base.resolve('/v1/registry/key'))).body) as Map)['publicKey']! as String;

    // Patient phone, with the registry key pinned at build time.
    final consent = ConsentStore();
    final audit = InMemoryAuditLog();
    final repo = await RecordRepository.open(SealedStore(InMemoryByteStore(), SecretKey(List.filled(32, 7))));
    await repo.savePatient(DemoData.patient('p-abc'));
    await repo.addAll(DemoData.records('p-abc'));
    await repo.saveProfile('p-abc', DemoData.profile(now));
    final me = await ReplyIdentity.create();
    final phone = ClinicalShareService(
      trust: RegistryTrust([SimplePublicKey(base64Decode(registryKey), type: KeyPairType.ed25519)]),
      consent: consent,
      access: RecordAccess(consent: consent, audit: audit, repository: repo),
      audit: audit,
      repository: repo,
      relay: HttpRelayClient(baseUrl: base, tokens: InMemoryWithdrawTokens(), client: client),
      replyIdentity: (_) async => me,
    );

    final doctor = await phone.scan(qr, now);
    await phone.share(patientId: 'p-abc', doctor: doctor, levels: {AccessLevel.summary, AccessLevel.familyIllnesses}, at: now);
    expect(relayStore.total, 1, reason: 'the relay holds one sealed share');

    // Doctor picks up with a signed request and opens the share.
    final mb = await RelayApi.doctorMailbox((await enc.extractPublicKey()).bytes);
    final pickup = await client.get(base.resolve(RelayApi.mailboxPath(mb)),
        headers: await RelayApi.doctorPickupHeaders(certificateQr: qr, signingKey: sign, mailbox: mb, at: DateTime.now().toUtc()));
    expect(pickup.statusCode, 200);
    final item = ((jsonDecode(pickup.body) as Map)['items']! as List).single as Map;
    final bundle = await ShareEnvelope.open(base64Decode(item['envelope']! as String), enc, now);
    expect((bundle['allergies']! as List).single, containsPair('substance', 'Penicillin'));
    expect(relayStore.total, 0, reason: 'pickup deleted it');

    // Doctor signs a prescription and seals it to the patient's reply key.
    final replyTo = (bundle['replyTo']! as Map).cast<String, Object?>();
    final rx = await SignedPrescription(
      patientId: bundle['patientRef']! as String,
      doctorRegistryId: 'DMC-12345',
      doctorName: 'Dr. R. Mehta',
      qualification: 'MBBS, MD',
      registrationNo: 'DMC-12345',
      medicine: 'Atorvastatin 10 mg',
      ingredient: 'atorvastatin',
      morning: 0,
      afternoon: 0,
      night: 1,
      days: 90,
      issuedAt: now,
    ).signedWith(sign);
    final key = base64Decode(replyTo['key']! as String);
    final sealed = await ShareEnvelope.seal(
      bundle: {'prescription': rx.toJson(), 'certificate': qr},
      recipientKey: key,
      keyId: await RelayApi.keyId(key),
      grantId: 'rx-1',
      expiresAt: now.add(const Duration(hours: 40)),
    );
    final put = await client.put(base.resolve(RelayApi.itemPath(replyTo['mailbox']! as String, 'rx-1')),
        body: sealed, headers: {RelayApi.hExpires: now.add(const Duration(hours: 40)).toIso8601String()});
    expect(put.statusCode, 201);

    // Patient collects it: verified, stored as signed, logged.
    final (added, refused) = await phone.collectPrescriptions('p-abc', now);
    expect(refused, 0);
    expect(added.single.provenance, Provenance.signed);
    expect(audit.entriesFor('p-abc').first.action, AuditAction.prescriptionReceived);
    expect(Uint8List.fromList(sealed).isNotEmpty, isTrue);
  });
}
