import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/identity_verifier.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// Hands back whatever attestation the test queues, as the LifeTrack server
/// would after DigiLocker.
class FakeVerifier implements IdentityVerifier {
  final List<IdentityAttestation> queue = [];
  String? lastPurpose;
  IdentityAttestation? lastParent;
  @override
  Future<VerifySession> start({required String purpose, IdentityAttestation? parent}) async {
    lastPurpose = purpose;
    lastParent = parent;
    return VerifySession(id: 's', secret: 'x', authorizeUrl: Uri.parse('http://127.0.0.1:8787/v1/practice-digilocker/authorize'));
  }

  @override
  Future<Map<String, Object?>> poll(VerifySession s) async => {'status': 'done', 'attestation': queue.removeAt(0).toJson()};
}

void main() {
  final now = DateTime(2026, 10, 1, 10);
  late SimpleKeyPair registry;
  late InMemoryIdDirectory dir;
  late FakeVerifier fake;

  Future<AppServices> phone(int k) async => AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, k)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
        relayOverride: (_) => InMemoryRelay(),
        idDirectoryOverride: () => dir,
        verifierOverride: () => fake,
        identityRequired: true,
      );

  Future<IdentityAttestation> att(String name, DateTime dob, String g, String subject, {IdentityMethod method = IdentityMethod.aadhaarDigiLocker, String? parent, SimpleKeyPair? signer}) =>
      IdentityAttestation(method: method, name: name, dateOfBirth: dob, gender: g, subjectHash: subject, verifiedAt: now, parentSubjectHash: parent).signedWith(signer ?? registry);

  Future<void> noBrowser(Uri _) async {}

  setUp(() async {
    registry = await Ed25519().newKeyPair();
    dir = InMemoryIdDirectory();
    fake = FakeVerifier();
  });

  test('no profile without DigiLocker; with it, the profile is exactly what DigiLocker confirmed', () async {
    final s = await phone(1);
    await expectLater(s.createProfile(name: 'Anyone', dob: DateTime(1990), sex: Sex.male), throwsA(isA<CustodyRefused>()));
    fake.queue.add(await att('Anjali Sharma', DateTime(1984, 6, 14), 'F', 'subj-anjali'));
    final v = await s.verifyWithDigiLocker(purpose: 'self', openUrl: noBrowser);
    final p = await s.createProfile(name: 'typed name is ignored', dob: DateTime(2000), sex: Sex.male, verification: v);
    expect((p.name, p.dateOfBirth, p.sex, p.isVerified), ('Anjali Sharma', DateTime(1984, 6, 14), Sex.female, true));
    expect(dir.entries.values.single['subject'], 'subj-anjali');
    expect(s.lifeTrackIdOf(p.id), isNotNull);
  });

  test('sample profiles are exempt — they are not people', () async {
    final s = await phone(1);
    await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    expect(s.currentPatient!.isVerified, isFalse);
  });

  test('one person, one profile: a second phone is told to restore instead', () async {
    final first = await phone(1);
    await first.createProfile(name: '', dob: DateTime(2000), sex: Sex.female, verification: await att('Anjali Sharma', DateTime(1984, 6, 14), 'F', 'subj-anjali'));
    final second = await phone(2);
    await expectLater(
      second.createProfile(name: '', dob: DateTime(2000), sex: Sex.female, verification: await att('Anjali Sharma', DateTime(1984, 6, 14), 'F', 'subj-anjali')),
      throwsA(isA<PersonExists>()),
    );
    expect(second.currentPatient, isNull, reason: 'the half-made profile is removed');
    expect(second.repository.patients, isEmpty);
  });

  test('a newborn only from the verified parent\'s own DigiLocker birth certificate — and that proves parenthood', () async {
    final s = await phone(1);
    await s.createProfile(name: '', dob: DateTime(2000), sex: Sex.female, verification: await att('Anjali Sharma', DateTime(1984, 6, 14), 'F', 'subj-anjali'));
    await expectLater(s.addChild(name: 'Baby', dob: DateTime(2026, 8, 20), sex: Sex.male, relation: 'son'), throwsA(isA<CustodyRefused>()));

    fake.queue.add(await att('Baby of Anjali Sharma', DateTime(2026, 8, 20), 'M', 'subj-bc-1', method: IdentityMethod.birthCertificateDigiLocker, parent: 'subj-anjali'));
    final v = await s.verifyWithDigiLocker(purpose: 'newborn', openUrl: noBrowser);
    expect(fake.lastParent!.subjectHash, 'subj-anjali', reason: 'the service is told who the verified parent is');
    final baby = await s.addChild(name: '', dob: DateTime(2000), sex: Sex.female, relation: 'son', verification: v);
    expect(baby.name, 'Baby of Anjali Sharma');
    expect(s.custodyOf(baby.id)!.method, ConsentMethod.birthCertificateDigiLocker);
    expect(s.custodyOf(baby.id)!.isVerified, isTrue);

    final someoneElses = await att('Other Baby', DateTime(2026, 9, 1), 'F', 'subj-bc-2', method: IdentityMethod.birthCertificateDigiLocker, parent: 'subj-stranger');
    await expectLater(s.addChild(name: '', dob: DateTime(2026), sex: Sex.female, relation: 'daughter', verification: someoneElses), throwsA(isA<CustodyRefused>()));
  });

  test('a newborn cannot be added until the parent is verified', () async {
    final s = await phone(1);
    await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    await expectLater(s.verifyWithDigiLocker(purpose: 'newborn', openUrl: noBrowser), throwsA(isA<VerificationFailed>()));
  });

  test('a result not signed by the LifeTrack service is refused', () async {
    final s = await phone(1);
    fake.queue.add(await att('Forged', DateTime(1990), 'M', 'subj-x', signer: await Ed25519().newKeyPair()));
    await expectLater(s.verifyWithDigiLocker(purpose: 'self', openUrl: noBrowser), throwsA(isA<VerificationFailed>()));
  });

  test('an adult who asks to be managed verifies with their own Aadhaar', () async {
    final s = await phone(1);
    await s.createProfile(name: '', dob: DateTime(2000), sex: Sex.female, verification: await att('Anjali Sharma', DateTime(1984, 6, 14), 'F', 'subj-anjali'));
    await expectLater(
      s.addDelegatingAdult(name: 'Ramesh Sharma', dob: DateTime(1955), sex: Sex.male, relation: 'father', typedName: 'Ramesh Sharma'),
      throwsA(isA<CustodyRefused>()),
    );
    final dad = await s.addDelegatingAdult(
      name: '', dob: DateTime(2000), sex: Sex.unspecified, relation: 'father', typedName: 'Ramesh Sharma',
      verification: await att('Ramesh Sharma', DateTime(1955, 1, 10), 'M', 'subj-ramesh'),
    );
    expect((dad.name, dad.isVerified), ('Ramesh Sharma', true));
  });
}
