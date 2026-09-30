import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/audit/log_view.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// A patient's phone, the LifeTrack service (relay + ID directory), and a
/// verified doctor who knows only the patient's 12-digit ID.
var _n = 0;

void main() {
  var now = DateTime(2026, 10, 1, 10);
  late InMemoryRelay relay;
  late InMemoryIdDirectory dir;
  late InMemoryRemoteVaultStore vault;
  late SimpleKeyPair registry;

  Future<AppServices> phone(int k) async => AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, k)),
        remote: vault,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
        relayOverride: (_) => relay,
        idDirectoryOverride: () => dir,
      );

  Future<(SimpleKeyPair enc, SimpleKeyPair sign, String qr)> doctor({SimpleKeyPair? signer}) async {
    final enc = await X25519().newKeyPair();
    final sign = await Ed25519().newKeyPair();
    final unsigned = DoctorCertificate(
      registryId: 'DMC-12345', name: 'Dr. R. Mehta', speciality: 'Cardiology', council: 'Delhi Medical Council', registrationNo: 'DMC-12345',
      encryptionKey: (await enc.extractPublicKey()).bytes, signingKey: (await sign.extractPublicKey()).bytes,
      issuedAt: DateTime(2026), expiresAt: DateTime(2027), signature: const [],
    );
    final sig = await Ed25519().sign(unsigned.signedBytes, keyPair: signer ?? registry);
    final cert = DoctorCertificate(
      registryId: unsigned.registryId, name: unsigned.name, speciality: unsigned.speciality, council: unsigned.council,
      registrationNo: unsigned.registrationNo, encryptionKey: unsigned.encryptionKey, signingKey: unsigned.signingKey,
      issuedAt: unsigned.issuedAt, expiresAt: unsigned.expiresAt, signature: sig.bytes,
    );
    return (enc, sign, cert.encode());
  }

  /// What the doctor web app does: look the ID up, sign, seal, deposit.
  Future<AccessRequest> request(String lifeTrackId, SimpleKeyPair sign, String qr, {List<String> levels = const ['summary', 'allReports']}) async {
    final entry = dir.entries[LifeTrackId.parse(lifeTrackId)!]!;
    final key = entry['key']! as List<int>;
    final r = await AccessRequest(
      requestId: 'req-${++_n}',
      lifeTrackId: LifeTrackId.parse(lifeTrackId)!,
      levels: levels,
      issuedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      certificate: qr,
      note: 'Follow-up for diabetes',
    ).signedWith(sign);
    await relay.deposit(
      mailbox: entry['mailbox']! as String,
      grantId: r.requestId,
      envelope: await ShareEnvelope.seal(bundle: r.toJson(), recipientKey: key, keyId: await RelayApi.keyId(key), grantId: r.requestId, expiresAt: r.expiresAt),
      expiresAt: r.expiresAt,
    );
    return r;
  }

  setUp(() async {
    now = DateTime(2026, 10, 1, 10);
    relay = InMemoryRelay();
    dir = InMemoryIdDirectory();
    vault = InMemoryRemoteVaultStore();
    registry = await Ed25519().newKeyPair();
  });

  test('every profile gets its own unique 12-digit ID, registered on the service', () async {
    final s = await phone(1);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final child = await s.addChild(name: 'Aarav', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    final a = s.lifeTrackIdOf(s.selfPatientId!)!, b = s.lifeTrackIdOf(child.id)!;
    expect(a, matches(RegExp(r'^1\d{11}$')));
    expect(LifeTrackId.parse(a), a);
    expect(a, isNot(b));
    expect(dir.entries.keys.toSet(), {a, b});
    expect(dir.entries[a]!.keys.toSet(), {'mailbox', 'key', 'tokenHash'}, reason: 'no name, no records');
  });

  test('a verified doctor asks by ID; nothing is shared until the patient approves', () async {
    final s = await phone(1);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female, demo: true);
    final (enc, sign, qr) = await doctor();
    await request(LifeTrackId.display(s.lifeTrackIdOf(s.selfPatientId!)!), sign, qr);

    final (_, handled, refused) = await s.checkInbox();
    expect((handled, refused), (1, 0));
    final pending = (await s.pendingRequests()).single;
    expect(pending.doctor.name, 'Dr. R. Mehta');
    expect(pending.levels, {AccessLevel.summary, AccessLevel.allReports});
    expect(relay.pending(await RelayApi.doctorMailbox(pending.doctor.encryptionKey)), 0, reason: 'nothing sent yet');
    final log = s.audit.entriesFor(s.selfPatientId!).first;
    expect((log.action, log.topic), (AuditAction.accessRequested, LogView.doctors));

    // The patient grants less than asked: Summary only.
    await s.sharing!.share(patientId: s.selfPatientId!, doctor: pending.doctor, levels: {AccessLevel.summary}, requested: pending.levels, at: now, grantorId: s.actingGrantor());
    await s.requests!.remove(pending.request.requestId);
    expect(await s.pendingRequests(), isEmpty);
    final envs = relay.pickUp(await RelayApi.doctorMailbox(pending.doctor.encryptionKey), now);
    final bundle = await ShareEnvelope.open(envs.single, enc, now);
    expect(bundle['withheld'], isNotEmpty, reason: 'the doctor is told what was not shared');
  });

  test('declining tells the doctor and is logged under Refused', () async {
    final s = await phone(1);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final (enc, sign, qr) = await doctor();
    await request(s.lifeTrackIdOf(s.selfPatientId!)!, sign, qr);
    await s.checkInbox();
    final p = (await s.pendingRequests()).single;
    await s.declineRequest(p);
    expect(await s.pendingRequests(), isEmpty);
    expect(s.audit.entriesFor(s.selfPatientId!).first.shownIn(LogView.refused), isTrue);
    final note = await ShareEnvelope.open(relay.pickUp(await RelayApi.doctorMailbox(p.doctor.encryptionKey), now).single, enc, now);
    expect(note, {'type': 'declined', 'requestId': p.request.requestId});
  });

  test('an unverified doctor, a forged signature or another ID is refused and logged', () async {
    final s = await phone(1);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final id = s.lifeTrackIdOf(s.selfPatientId!)!;
    final (_, sign, qrFake) = await doctor(signer: await Ed25519().newKeyPair());
    await request(id, sign, qrFake);
    final (_, _, qr) = await doctor();
    await request(id, await Ed25519().newKeyPair(), qr); // signed by someone else's key
    final (_, refused1, refused) = await s.checkInbox();
    expect((refused1, refused), (0, 2));
    expect(await s.pendingRequests(), isEmpty);
    expect(s.audit.entriesFor(s.selfPatientId!).where((e) => e.action == AuditAction.denied), hasLength(2));
  });

  test('restoring a backup on a new phone keeps the same ID, now reaching the new phone', () async {
    final old = await phone(1);
    await old.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final id = old.lifeTrackIdOf(old.selfPatientId!)!;
    final kit = await old.setUpBackup();
    final fresh = await phone(2);
    await fresh.restoreFromBackup(account: kit.account, password: kit.password);
    expect(fresh.lifeTrackIdOf(fresh.selfPatientId!), id);
    final (_, sign, qr) = await doctor();
    await request(id, sign, qr);
    await fresh.checkInbox();
    expect(await fresh.pendingRequests(), hasLength(1), reason: 'the request reached the new phone');
  });

  test('erasing a profile removes its ID from the service', () async {
    final s = await phone(1);
    await s.createProfile(name: 'Solo', dob: DateTime(1990), sex: Sex.male);
    expect(dir.entries, hasLength(1));
    await s.eraseProfile();
    expect(dir.entries, isEmpty);
  });
}
