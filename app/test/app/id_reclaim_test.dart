import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/identity_verifier.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// An ID directory that can be unreachable.
class FlakyDirectory extends InMemoryIdDirectory {
  bool down = false;

  void _check() {
    if (down) throw StateError('Connection refused');
  }

  @override
  Future<void> delete({required String id, required String token}) async {
    _check();
    await super.delete(id: id, token: token);
  }

  @override
  Future<String> reclaim({required String mailbox, required List<int> key, required String tokenHash, required IdentityAttestation attestation}) async {
    _check();
    return super.reclaim(mailbox: mailbox, key: key, tokenHash: tokenHash, attestation: attestation);
  }
}

void main() {
  var now = DateTime(2026, 11, 6, 10);
  late SimpleKeyPair registry;
  late FlakyDirectory dir;
  late InMemoryRemoteVaultStore vault;

  Future<AppServices> phone(int k, {ByteStore? bytes}) async => AppServices.open(
        bytes: bytes ?? InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, k)),
        remote: vault,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
        relayOverride: (_) => InMemoryRelay(),
        idDirectoryOverride: () => dir,
        retryAfter: null,
      );

  Future<IdentityAttestation> check({DateTime? at}) => IdentityAttestation(
        method: IdentityMethod.aadhaarDigiLocker,
        name: 'Anjali Sharma',
        dateOfBirth: DateTime(1984, 6, 14),
        gender: 'F',
        subjectHash: 'subject-anjali',
        verifiedAt: at ?? now,
      ).signedWith(registry);

  Future<Patient> create(AppServices s, {bool move = false, DateTime? checkedAt}) async =>
      s.createProfile(name: '', dob: DateTime(2000), sex: Sex.female, verification: await check(at: checkedAt), moveExistingId: move);

  setUp(() async {
    now = DateTime(2026, 11, 6, 10);
    registry = await Ed25519().newKeyPair();
    dir = FlakyDirectory();
    vault = InMemoryRemoteVaultStore();
  });

  group('reinstalled with no backup', () {
    test('a fresh check brings the same ID back, on a choice made by the person', () async {
      final old = await phone(1);
      final me = await create(old);
      final id = old.lifeTrackIdOf(me.id)!;

      now = now.add(const Duration(days: 40));
      final fresh = await phone(2);
      await expectLater(create(fresh), throwsA(isA<PersonExists>()), reason: 'never without asking');
      expect(fresh.repository.patients, isEmpty);

      final back = await create(fresh, move: true);
      expect(fresh.lifeTrackIdOf(back.id), id);
      expect(fresh.currentPatient!.isVerified, isTrue);
      expect(fresh.audit.entriesFor(back.id).map((e) => e.detail), contains('Moving the LifeTrack ID to this phone with a new identity check'));
    });

    test('a check too old to count leaves no half-made profile', () async {
      final old = await phone(1);
      await create(old);
      final fresh = await phone(2);
      await expectLater(create(fresh, move: true, checkedAt: now.subtract(const Duration(days: 1))), throwsA(isA<ReclaimRefused>()));
      expect(fresh.repository.patients, isEmpty);
      expect(fresh.currentPatient, isNull);
    });

    test('offline, the move fails plainly and can be tried again', () async {
      final old = await phone(1);
      final id = old.lifeTrackIdOf((await create(old)).id)!;
      now = now.add(const Duration(minutes: 5));
      dir.down = true;
      final fresh = await phone(2);
      await expectLater(create(fresh, move: true), throwsA(isA<StateError>()));
      expect(fresh.repository.patients, isEmpty);
      dir.down = false;
      final p = await create(fresh, move: true);
      expect(fresh.lifeTrackIdOf(p.id), id);
    });

    test('the phone that lost the ID can still erase, and drops what it holds', () async {
      final old = await phone(1);
      await create(old);
      now = now.add(const Duration(days: 1));
      final fresh = await phone(2);
      final p = await create(fresh, move: true);
      await old.eraseProfile();
      expect(await old.ids!.retryRemovals(), 0, reason: 'nothing left to retry: the ID is not its to delete');
      expect(dir.entries, hasLength(1), reason: "the new phone's ID stays");
      expect(fresh.lifeTrackIdOf(p.id), isNotNull);
    });
  });

  group('erased with the server off', () {
    test('the token is kept until the server has really deleted the ID', () async {
      final s = await phone(1);
      await create(s);
      dir.down = true;
      await s.eraseProfile();
      expect(dir.entries, hasLength(1), reason: 'still on the server');

      dir.down = false;
      await s.retryNow();
      expect(dir.entries, isEmpty, reason: 'this used to be impossible: the token had been thrown away');
    });

    test('it survives a restart', () async {
      final bytes = InMemoryByteStore();
      final s = await phone(1, bytes: bytes);
      await create(s);
      dir.down = true;
      await s.eraseProfile();
      dir.down = false;
      final again = await phone(1, bytes: bytes);
      await again.retryNow();
      expect(dir.entries, isEmpty);
    });

    test('making the same person again finishes the deletion first, so nothing blocks them', () async {
      final s = await phone(1);
      await create(s);
      dir.down = true;
      await s.eraseProfile();
      dir.down = false;
      now = now.add(const Duration(minutes: 1));
      final p = await create(s);
      expect(s.lifeTrackIdOf(p.id), isNotNull);
      expect(dir.entries, hasLength(1));
    });

    test('an ID on its way out is not offered, and does not go in a backup', () async {
      final s = await phone(1);
      final p = await create(s);
      final id = s.lifeTrackIdOf(p.id)!;
      final ids = s.ids!;
      dir.down = true;
      await expectLater(ids.remove(p.id), throwsStateError);
      expect(ids.idOf(p.id), isNull);
      expect(ids.profileFor(id), isNull);
      expect(ids.export(), isEmpty);
    });

    test('the erasure of the owner still leaves the log entry', () async {
      final s = await phone(1);
      final p = await create(s);
      dir.down = true;
      await s.eraseProfile();
      expect(s.audit.entriesFor(p.id).single.action, AuditAction.erasure);
    });
  });
}
