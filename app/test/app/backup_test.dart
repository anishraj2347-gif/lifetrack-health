import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// One backup service, two phones: the old one that is lost, a new one.
void main() {
  final now = DateTime(2026, 10, 1, 10);
  late InMemoryRemoteVaultStore server;

  Future<AppServices> phone(int key) => AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, key)),
        remote: server,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );

  Future<(AppServices, RecoveryKit)> oldPhone({bool notes = false}) async {
    final s = await phone(1);
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female, demo: true);
    await s.addChild(name: 'Aarav Sharma', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    await s.saveEmergencyCard(me.id, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    await s.addRecord(HealthRecord(id: 'n1', patientId: me.id, kind: RecordKind.note, title: 'Felt dizzy', date: now, source: RecordSource.typedByPatient));
    await s.attachments.save('a1', [Uint8List.fromList([1, 2, 3])]);
    await s.addRecord(HealthRecord(id: 'r1', patientId: me.id, kind: RecordKind.report, title: 'Lipid panel', date: now, source: RecordSource.smartCapture, attachmentId: 'a1'));
    return (s, await s.setUpBackup(includeNotes: notes));
  }

  setUp(() => server = InMemoryRemoteVaultStore());

  test('a new phone gets everything back with the account code and password', () async {
    final (old, kit) = await oldPhone();
    expect(kit.account, matches(RegExp(r'^LT-[0-9A-Z]{5}-[0-9A-Z]{5}$')));
    expect(kit.password, matches(RegExp(r'^([0-9A-Z]{5}-){3}[0-9A-Z]{5}$')));

    final fresh = await phone(2);
    final n = await fresh.restoreFromBackup(account: kit.account.toLowerCase().replaceAll('-', ' '), password: kit.password.toLowerCase());
    expect(n, old.repository.patients.map((p) => old.repository.recordsOf(p.id).length).reduce((a, b) => a + b) - 1, reason: 'all but the personal note');
    expect(fresh.familyOnPhone().map((p) => p.name), ['Anjali Sharma', 'Aarav Sharma']);
    expect(fresh.custodyOf(fresh.familyOnPhone()[1].id)!.kind, CustodyKind.childOfParent);
    expect((await fresh.emergency.load(fresh.selfPatientId!)).allergies, 'Penicillin');
    expect(await fresh.attachments.load('a1'), [Uint8List.fromList([1, 2, 3])]);
    expect(fresh.repository.recordsOf(fresh.selfPatientId!).any((r) => r.kind == RecordKind.note), isFalse);
    expect(fresh.backupAccount, kit.account, reason: 'the new phone keeps backing up to the same account');
    expect(fresh.audit.entriesFor(fresh.selfPatientId!).first.action, AuditAction.vaultRestore);
  });

  test('any two recovery codes open it without the password; one does not', () async {
    final (old, kit) = await oldPhone();
    final fresh = await phone(2);
    await expectLater(fresh.restoreFromBackup(account: kit.account, codes: [kit.printCode]), throwsArgumentError);
    await fresh.restoreFromBackup(account: kit.account, codes: [kit.printCode, old.phoneRecoveryCode!]);
    expect(fresh.familyOnPhone(), hasLength(2));
    // …and that phone can keep backing up without ever knowing the password.
    await fresh.addRecord(HealthRecord(id: 'r2', patientId: fresh.selfPatientId!, kind: RecordKind.report, title: 'HbA1c', date: now, source: RecordSource.smartCapture));
    expect(fresh.lastBackupError, isNull);
    final third = await phone(3);
    await third.restoreFromBackup(account: kit.account, password: kit.password);
    expect(third.repository.recordsOf(third.selfPatientId!).map((r) => r.id), contains('r2'));
  });

  test('a wrong password is refused, and restore never merges into an existing profile', () async {
    final (old, kit) = await oldPhone();
    final fresh = await phone(2);
    await expectLater(fresh.restoreFromBackup(account: kit.account, password: AppServices.newBackupPassword()), throwsA(isA<VaultAuthenticationFailed>()));
    await expectLater(old.restoreFromBackup(account: kit.account, password: kit.password), throwsA(isA<CustodyRefused>()));
  });

  test('changes are backed up as they happen; personal notes only when chosen', () async {
    final (old, kit) = await oldPhone(notes: true);
    await old.addRecord(HealthRecord(id: 'r9', patientId: old.selfPatientId!, kind: RecordKind.prescription, title: 'Metformin', date: now, source: RecordSource.smartCapture));
    final fresh = await phone(2);
    await fresh.restoreFromBackup(account: kit.account, password: kit.password);
    final ids = fresh.repository.recordsOf(fresh.selfPatientId!).map((r) => r.id);
    expect(ids, containsAll(['r9', 'n1']));
  });

  test('turning backup off, or erasing the owner, deletes it from the server', () async {
    final (old, _) = await oldPhone();
    expect(server.isEmpty, isFalse);
    await old.turnOffBackup();
    expect(server.isEmpty, isTrue);
    expect(old.backupAccount, isNull);

    final s = await phone(4);
    await s.createProfile(name: 'Solo', dob: DateTime(1990), sex: Sex.male);
    await s.setUpBackup();
    await s.eraseProfile();
    expect(server.isEmpty, isTrue);
  });

  test('passwords are typed forgivingly', () {
    expect(AppServices.normalisePassword('k7qm2 xpa9d-hr4tw b63ne'), 'K7QM2-XPA9D-HR4TW-B63NE');
    expect(AppServices.normalisePassword('KOQM2'), 'K0QM2', reason: 'O is read as zero');
    expect(AppServices.normaliseAccount('lt 7kqm2 xpa9d'), 'LT-7KQM2-XPA9D');
  });
}
