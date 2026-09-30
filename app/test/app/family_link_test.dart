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
