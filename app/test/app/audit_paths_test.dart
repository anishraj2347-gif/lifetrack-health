import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/audit/log_view.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/family/family_link.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

import '../support/offline.dart';

/// A store that can be told to refuse writes of one blob.
class FailingStore extends InMemoryByteStore {
  String? failing;
  int failuresLeft = 0;

  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (name == failing && failuresLeft > 0) {
      failuresLeft--;
      throw StateError('disk full');
    }
    await super.write(name, bytes);
  }
}

void main() {
  final now = DateTime(2026, 9, 30, 11, 30);
  late SimpleKeyPair registry;
  late SwitchableRelay relay;
  late TestDoctor doctor;

  setUp(() async {
    registry = await Ed25519().newKeyPair();
    relay = SwitchableRelay();
    doctor = await TestDoctor.make(registry);
  });

  TestPhone phone() => TestPhone(relay: relay, registry: registry, now: () => now);

  Future<AppServices> withProfile(TestPhone p, String name) async {
    final s = await p.open();
    await s.createProfile(name: name, dob: DateTime(1984), sex: Sex.female);
    return s;
  }

  group('erasure', () {
    test('a live share ends when the profile is erased, and the doctor is told', () async {
      final s = await withProfile(phone(), 'Anjali Sharma');
      final id = s.selfPatientId!;
      final r = await s.sharing!.share(patientId: id, doctor: doctor.cert, levels: {AccessLevel.summary}, at: now);
      final bundle = (await doctor.pickUp(relay.inner, now)).single;

      expect(await s.eraseProfile(), 0);

      final close = (await doctor.pickUp(relay.inner, now)).single;
      expect((close['type'], close['grantId'], close['closeSecret']), ('close', r.grant.id, bundle['closeSecret']));
      final entry = s.audit.entriesFor(id).single;
      expect(entry.action, AuditAction.erasure);
      expect(entry.detail, contains('access ended for 1 doctor'));
    });

    test('offline, the records still go; the doctor is told when the server is back', () async {
      final s = await withProfile(phone(), 'Anjali Sharma');
      final id = s.selfPatientId!;
      await s.sharing!.share(patientId: id, doctor: doctor.cert, levels: {AccessLevel.summary}, at: now);
      await doctor.pickUp(relay.inner, now);
      relay.down = true;

      expect(await s.eraseProfile(), 1);

      expect(s.repository.patients, isEmpty);
      expect(s.audit.entriesFor(id).single.detail, contains('1 not told yet'));
      relay.down = false;
      await s.retryNow();
      expect((await doctor.pickUp(relay.inner, now)).single['type'], 'close', reason: 'the message outlives the profile');
      expect(s.audit.entriesFor(id), hasLength(1), reason: 'the erasure stays the only entry');
    });

    test('with no share there is nothing to tell, and the entry reads as before', () async {
      final s = await withProfile(phone(), 'Anjali Sharma');
      final id = s.selfPatientId!;
      expect(await s.eraseProfile(), 0);
      expect(s.audit.entriesFor(id).single.detail, 'records, grants, Emergency ID and backup deleted');
    });

    test("erasing a child ends only the child's shares", () async {
      final s = await withProfile(phone(), 'Anjali Sharma');
      final me = s.selfPatientId!;
      final child = await s.addChild(name: 'Aarav Sharma', dob: DateTime(2019), sex: Sex.male, relation: 'son');
      final mine = await s.sharing!.share(patientId: me, doctor: doctor.cert, levels: {AccessLevel.summary}, at: now);
      await s.sharing!.share(patientId: child.id, doctor: doctor.cert, levels: {AccessLevel.summary}, at: now);
      await doctor.pickUp(relay.inner, now);
      await s.switchTo(child.id);
      await s.eraseProfile();
      expect(s.consent.activeGrantsFor(me, now).map((g) => g.id), [mine.grant.id]);
      expect((await doctor.pickUp(relay.inner, now)), hasLength(1));
    });
  });

  group('family link', () {
    Future<(AppServices, AppServices, FamilyLink)> linked() async {
      final anjali = await withProfile(phone(), 'Anjali Sharma');
      final vikram = await withProfile(phone(), 'Vikram Sharma');
      await vikram.emergency.save(vikram.selfPatientId!, const EmergencyCard(bloodType: 'B+'));
      final link = await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: true, shareMedicines: true);
      await anjali.checkInbox();
      return (anjali, vikram, link);
    }

    List<AuditEntry> log(AppServices s) => s.audit.entriesFor(s.selfPatientId!);

    test('joining is on the record before the invite answer leaves', () async {
      final anjali = await withProfile(phone(), 'Anjali Sharma');
      final vikram = await withProfile(phone(), 'Vikram Sharma');
      final code = (await anjali.createFamilyInvite()).encode();
      final seen = <String?>[];
      relay.onCall = () => seen.add(vikram.audit.entriesFor(vikram.selfPatientId!).first.detail);
      await vikram.joinFamily(code: code, shareEmergency: true, shareMedicines: false);
      expect(seen.single, 'Linking with Anjali Sharma; shares Emergency ID');
      expect(log(vikram).first.topic, LogView.family);
    });

    test('a failed join stays on the record, and leaves no link', () async {
      final anjali = await withProfile(phone(), 'Anjali Sharma');
      final vikram = await withProfile(phone(), 'Vikram Sharma');
      final code = (await anjali.createFamilyInvite()).encode();
      relay.down = true;
      await expectLater(vikram.joinFamily(code: code, shareEmergency: true, shareMedicines: false), throwsA(isA<SocketLikeFailure>()));
      expect(await vikram.links!.links(), isEmpty);
      expect(log(vikram).map((e) => e.detail), containsAllInOrder(['Not linked with Anjali Sharma: the message could not be sent', 'Linking with Anjali Sharma; shares Emergency ID']));
    });

    test('every update is logged before it leaves, naming what was sent and to whom', () async {
      final (_, vikram, _) = await linked();
      final seen = <AuditEntry>[];
      relay.onCall = () => seen.add(log(vikram).first);
      await vikram.refreshFamilyLinks();
      expect(seen.single.action, AuditAction.familyShare);
      expect(seen.single.detail, 'Sending Emergency ID and medicines to Anjali Sharma');
      expect(seen.single.topic, LogView.family);
    });

    test('an update that could not be sent says so', () async {
      final (_, vikram, _) = await linked();
      relay.down = true;
      await expectLater(vikram.refreshFamilyLinks(), throwsA(isA<SocketLikeFailure>()));
      expect(log(vikram).first.detail, 'Not sent to Anjali Sharma: the message could not be sent');
    });

    test('changing what is shared logs the send first, then the choice', () async {
      final (_, vikram, link) = await linked();
      final seen = <String?>[];
      relay.onCall = () => seen.add(log(vikram).first.detail);
      await vikram.changeFamilySharing(link, emergency: true, medicines: false);
      expect(seen.single, 'Sending Emergency ID to Anjali Sharma');
      expect(log(vikram).first.detail, 'Now sharing Emergency ID with Anjali Sharma');
    });

    test('an unlink is logged before it leaves; offline it still unlinks and says who was not told', () async {
      final (_, vikram, link) = await linked();
      final seen = <String?>[];
      relay.onCall = () => seen.add(log(vikram).first.detail);
      relay.down = true;
      await expectLater(vikram.unlinkFamily(link), throwsA(isA<SocketLikeFailure>()));
      expect(seen.single, 'Unlinked from Anjali Sharma');
      expect(await vikram.links!.links(), isEmpty);
      expect(log(vikram).first.detail, contains('could not be told'));
    });
  });

  group('saving grants', () {
    Future<(AppServices, FailingStore)> open() async {
      final store = FailingStore();
      final s = await AppServices.open(bytes: store, deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(), kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, retryAfter: null);
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      return (s, store);
    }

    Future<AppServices> reopen(FailingStore store) => AppServices.open(bytes: store, deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(), kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, retryAfter: null);

    test('one failed write does not stop later revocations being saved', () async {
      final (s, store) = await open();
      await s.enableInsights();
      await s.flush();
      final g = s.activeGrants().single;
      store
        ..failing = 'grants'
        ..failuresLeft = 1;
      s.consent.onChanged!(s.consent); // this write fails, and used to break the chain for good
      await Future<void>.delayed(const Duration(milliseconds: 10));
      s.consent.revoke(g.id); // the next write must carry it
      expect(await s.flush(), isTrue);
      expect((await reopen(store)).activeGrants(), isEmpty, reason: 'the revocation is on disk');
    });

    test('a revocation the phone could not save is reported, not swallowed', () async {
      final (s, store) = await open();
      await s.enableInsights();
      await s.flush();
      final g = s.activeGrants().single;
      store
        ..failing = 'grants'
        ..failuresLeft = 2;
      await expectLater(s.revoke(g), throwsStateError);
      expect(s.activeGrants(), isEmpty, reason: 'in memory it has ended');
      expect(await s.flush(), isTrue);
      expect((await reopen(store)).activeGrants(), isEmpty, reason: 'the retry saved it');
    });
  });
}
