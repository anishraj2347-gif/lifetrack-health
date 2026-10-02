import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/family/family_link.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Two phones, one relay: Anjali invites her husband Vikram, who keeps his
/// own records on his own phone.
void main() {
  var now = DateTime(2026, 9, 30, 10);
  late InMemoryRelay relay;

  Future<AppServices> phone(String name, int key) async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, key)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
      share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode(List.filled(32, 9))),
      relayOverride: (_) => relay,
    );
    await s.createProfile(name: name, dob: DateTime(1982), sex: Sex.unspecified);
    return s;
  }

  setUp(() {
    now = DateTime(2026, 9, 30, 10);
    relay = InMemoryRelay();
  });

  test('an invite survives being typed or scanned, and rejects anything else', () {
    final i = FamilyInvite(id: 'ab12', fromName: 'Anjali Sharma', mailbox: 'p-x', key: 'k', expiresAt: DateTime.utc(2026, 10, 7));
    final back = FamilyInvite.decode('  ${i.encode()}\n');
    expect((back.id, back.fromName, back.mailbox, back.expiresAt), (i.id, i.fromName, i.mailbox, i.expiresAt));
    expect(() => FamilyInvite.decode('hello'), throwsFormatException);
    expect(() => FamilyInvite.decode('LTF1.###'), throwsFormatException);
  });

  test('the joining adult shares only what they choose; the inviter receives it encrypted via the relay', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.emergency.save(vikram.selfPatientId!, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    await vikram.addRecord(HealthRecord(
      id: 'rx1',
      patientId: vikram.selfPatientId!,
      kind: RecordKind.prescription,
      title: 'Amlodipine 5 mg',
      date: DateTime(2026, 9, 1),
      source: RecordSource.smartCapture,
      dose: const Dose(morning: 1, afternoon: 0, night: 0),
    ));

    final invite = await anjali.createFamilyInvite();
    final mine = await vikram.joinFamily(code: invite.encode(), shareEmergency: true, shareMedicines: false);
    expect(mine.name, 'Anjali Sharma');

    final (added, handled, refused) = await anjali.checkInbox();
    expect((added, handled, refused), (0, 1, 0));
    final link = (await anjali.links!.links()).single;
    expect(link.name, 'Vikram Sharma');
    expect(link.theirEmergency!['blood'], 'B+');
    expect(link.theirMedicines, isNull, reason: 'he did not share medicines');
    expect(anjali.repository.recordsOf(vikram.selfPatientId!), isEmpty, reason: 'linking never copies records');

    // He changes his mind and shares medicines too.
    await vikram.links!.links().then((ls) async {
      final l = ls.single;
      await vikram.links!.sendUpdate(
        ownerId: vikram.selfPatientId!,
        link: FamilyLink.fromJson({...l.toJson(), 'shareMed': true}),
        emergency: await vikram.emergency.load(vikram.selfPatientId!),
        activeMedicines: vikram.repository.recordsOf(vikram.selfPatientId!),
        at: now,
      );
    });
    await anjali.checkInbox();
    expect(((await anjali.links!.links()).single.theirMedicines!.single as Map)['title'], 'Amlodipine 5 mg');
  });

  test('an invite works once, and not after 7 days', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    final code = (await anjali.createFamilyInvite()).encode();
    now = now.add(const Duration(days: 7, minutes: 1));
    await expectLater(vikram.joinFamily(code: code, shareEmergency: false, shareMedicines: false), throwsA(isA<LinkRefused>()));

    now = DateTime(2026, 9, 30, 10);
    final code2 = (await anjali.createFamilyInvite()).encode();
    await vikram.joinFamily(code: code2, shareEmergency: false, shareMedicines: false);
    final other = await phone('Someone Else', 3);
    await other.joinFamily(code: code2, shareEmergency: false, shareMedicines: false);
    final (_, handled, refused) = await anjali.checkInbox();
    expect((handled, refused), (1, 1), reason: 'the second use of the same invite is refused');
  });

  test('someone who saw the invite code cannot send updates or unlink in either name', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.emergency.save(vikram.selfPatientId!, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    final invite = await anjali.createFamilyInvite();
    await vikram.joinFamily(code: invite.encode(), shareEmergency: true, shareMedicines: false);
    await anjali.checkInbox();

    // The invite code (sent over a chat app) names Anjali's mailbox and key
    // and the link's id. With them, someone forges "Vikram's" new card…
    final seen = FamilyInvite.decode(invite.encode());
    Future<void> forge(Map<String, Object?> payload) async {
      final key = base64Decode(seen.key);
      await relay.deposit(
        mailbox: seen.mailbox,
        grantId: 'forged-${payload.hashCode}',
        envelope: await ShareEnvelope.seal(bundle: payload, recipientKey: key, keyId: await RelayApi.keyId(key), grantId: 'f', expiresAt: now.add(const Duration(hours: 1))),
        expiresAt: now.add(const Duration(hours: 1)),
      );
    }

    await forge({'type': 'family_link_update', 'linkId': seen.id, 'emergency': {'blood': 'O+', 'allergies': 'None'}, 'medicines': null});
    await forge({'type': 'family_link_update', 'linkId': seen.id, 'linkSecret': 'a guess of sixteen+ chars', 'emergency': {'blood': 'O+'}});
    await forge({'type': 'family_unlink', 'linkId': seen.id});
    final (_, handled, refused) = await anjali.checkInbox();
    expect((handled, refused), (0, 3));
    final link = (await anjali.links!.links()).single;
    expect((link.theirEmergency!['blood'], link.theirEmergency!['allergies']), ('B+', 'Penicillin'));
    expect(anjali.audit.entriesFor(anjali.selfPatientId!).where((e) => e.detail?.contains('did not come from the linked phone') ?? false), hasLength(3));
  });

  test('both phones show the same safety code for a link', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: false, shareMedicines: false);
    await anjali.checkInbox();
    final a = (await anjali.links!.links()).single.safetyCode;
    expect(a, matches(RegExp(r'^[0-9A-Z]{4} [0-9A-Z]{4}$')));
    expect((await vikram.links!.links()).single.safetyCode, a);
  });

  test('what a linked phone sends is cut down to the Emergency ID fields and bounded', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: false, shareMedicines: false);
    await anjali.checkInbox();
    final l = (await vikram.links!.links()).single;
    final key = base64Decode(l.theirKey);
    await relay.deposit(
      mailbox: l.theirMailbox,
      grantId: 'big',
      envelope: await ShareEnvelope.seal(bundle: {
        'type': 'family_link_update',
        'linkId': l.id,
        'linkSecret': l.secret,
        'emergency': {'blood': 'not a blood group', 'allergies': 'x' * 5000, 'extra': 'kept nowhere'},
        'medicines': [for (var i = 0; i < 500; i++) {'title': 'M$i', 'dose': '1-0-0'}],
      }, recipientKey: key, keyId: await RelayApi.keyId(key), grantId: 'big', expiresAt: now.add(const Duration(hours: 1))),
      expiresAt: now.add(const Duration(hours: 1)),
    );
    await anjali.checkInbox();
    final got = (await anjali.links!.links()).single;
    expect(got.theirEmergency!['blood'], '');
    expect((got.theirEmergency!['allergies']! as String).length, EmergencyCard.maxFieldLength);
    expect(got.theirEmergency!.containsKey('extra'), isFalse);
    expect(got.theirMedicines, hasLength(50));
  });

  test('you cannot join your own invite', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final code = (await anjali.createFamilyInvite()).encode();
    await expectLater(anjali.joinFamily(code: code, shareEmergency: true, shareMedicines: true), throwsA(isA<LinkRefused>()));
  });

  test('either side can unlink, and the other phone deletes what it held', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.emergency.save(vikram.selfPatientId!, const EmergencyCard(bloodType: 'B+'));
    await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: true, shareMedicines: false);
    await anjali.checkInbox();
    expect(await anjali.links!.links(), hasLength(1));

    await vikram.unlinkFamily((await vikram.links!.links()).single);
    expect(await vikram.links!.links(), isEmpty);
    await anjali.checkInbox();
    expect(await anjali.links!.links(), isEmpty);
  });

  test('a new medicine or Emergency ID change reaches linked family on its own', () async {
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: true, shareMedicines: true);
    await anjali.checkInbox();
    expect((await anjali.links!.links()).single.theirMedicines, isEmpty);

    await vikram.addRecord(HealthRecord(
      id: 'rx2',
      patientId: vikram.selfPatientId!,
      kind: RecordKind.prescription,
      title: 'Telmisartan 40 mg',
      date: now,
      source: RecordSource.smartCapture,
    ));
    await vikram.saveEmergencyCard(vikram.selfPatientId!, const EmergencyCard(bloodType: 'O+'));
    await anjali.checkInbox();
    final l = (await anjali.links!.links()).single;
    expect((l.theirMedicines!.single as Map)['title'], 'Telmisartan 40 mg');
    expect(l.theirEmergency!['blood'], 'O+');
  });

  test('saving still works when the relay is unreachable', () async {
    final flaky = _FlakyRelay();
    relay = flaky;
    final anjali = await phone('Anjali Sharma', 1);
    final vikram = await phone('Vikram Sharma', 2);
    await vikram.joinFamily(code: (await anjali.createFamilyInvite()).encode(), shareEmergency: true, shareMedicines: false);
    flaky.down = true;
    await vikram.saveEmergencyCard(vikram.selfPatientId!, const EmergencyCard(bloodType: 'A+'));
    expect((await vikram.emergency.load(vikram.selfPatientId!)).bloodType, 'A+');
  });
}

class _FlakyRelay extends InMemoryRelay {
  bool down = false;
  @override
  Future<void> deposit({required String mailbox, required String grantId, required Uint8List envelope, required DateTime expiresAt}) =>
      down ? Future.error(StateError('relay down')) : super.deposit(mailbox: mailbox, grantId: grantId, envelope: envelope, expiresAt: expiresAt);
}
