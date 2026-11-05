import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vaccines/uip_schedule.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// The app dies at write number [dieAfter]: that write and all later ones
/// never reach the store underneath, as when the process is killed.
class DyingStore implements ByteStore {
  DyingStore(this.inner, {this.dieAfter});
  final ByteStore inner;
  int? dieAfter;
  int writes = 0;

  void _tick() {
    final d = dieAfter;
    if (d != null && writes++ >= d) throw StateError('killed');
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    _tick();
    await inner.write(name, bytes);
  }

  @override
  Future<void> delete(String name) async {
    _tick();
    await inner.delete(name);
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);
  @override
  Future<List<String>> names() => inner.names();
}

void main() {
  final now = DateTime(2026, 10, 1, 10);
  late InMemoryRemoteVaultStore server;
  late InMemoryIdDirectory dir;
  late RecoveryKit kit;

  Future<AppServices> open(ByteStore bytes, {int key = 2}) => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, key)),
        remote: server,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        retryAfter: null,
      );

  Future<void> makeBackup() async {
    final s = await open(InMemoryByteStore(), key: 1);
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female, demo: true);
    await s.addChild(name: 'Aarav Sharma', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    await s.saveEmergencyCard(me.id, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    await s.attachments.save('a1', [Uint8List.fromList([1, 2, 3])]);
    await s.addRecord(HealthRecord(id: 'r1', patientId: me.id, kind: RecordKind.report, title: 'Lipid panel', date: now, source: RecordSource.smartCapture, attachmentId: 'a1'));
    await s.markVaccine(s.familyOnPhone()[1].id, 'bcg', VaccineGiven(on: DateTime(2019, 2)));
    kit = await s.setUpBackup();
    await s.settle();
  }

  setUp(() async {
    server = InMemoryRemoteVaultStore();
    dir = InMemoryIdDirectory();
    await makeBackup();
  });

  Future<void> expectWhole(AppServices s) async {
    expect(s.restoreInterrupted, isFalse);
    expect(s.familyOnPhone().map((p) => p.name), ['Anjali Sharma', 'Aarav Sharma']);
    expect(s.currentPatient!.name, 'Anjali Sharma');
    expect(s.repository.recordsOf(s.selfPatientId!).map((r) => r.id), contains('r1'));
    expect((await s.emergency.load(s.selfPatientId!)).allergies, 'Penicillin');
    expect(await s.attachments.load('a1'), [Uint8List.fromList([1, 2, 3])]);
    expect(s.vaccinesOf(s.familyOnPhone()[1].id), contains('bcg'));
    expect(s.backupAccount, kit.account);
  }

  test('killed at any write, the app opens to a retry that brings everything back', () async {
    // Counts the writes of a clean restore, to walk every point in it.
    final counting = DyingStore(InMemoryByteStore(), dieAfter: 1 << 30);
    await (await open(counting)).restoreFromBackup(account: kit.account, password: kit.password);
    final total = counting.writes;
    expect(total, greaterThan(10));

    for (var k = 0; k < total; k++) {
      final disk = InMemoryByteStore();
      final dying = await open(DyingStore(disk, dieAfter: k));
      try {
        await dying.restoreFromBackup(account: kit.account, password: kit.password);
      } on StateError {
        // The kill.
      }

      final reopened = await open(disk);
      if (reopened.currentPatient != null) {
        await expectWhole(reopened); // it died after the completion mark
        continue;
      }
      expect(reopened.currentPatient, isNull, reason: 'write $k: the welcome screen shows');
      await reopened.restoreFromBackup(account: kit.account, password: kit.password);
      await expectWhole(reopened);
      await expectWhole(await open(disk));
    }
  });

  group('after an interrupted restore', () {
    Future<(InMemoryByteStore, AppServices)> interrupted() async {
      final disk = InMemoryByteStore();
      final dying = await open(DyingStore(disk, dieAfter: 14));
      await expectLater(dying.restoreFromBackup(account: kit.account, password: kit.password), throwsStateError);
      final s = await open(disk);
      expect(s.restoreInterrupted, isTrue);
      expect(s.interruptedRestoreAccount, kit.account);
      return (disk, s);
    }

    test('a wrong password changes nothing and can be corrected', () async {
      final (_, s) = await interrupted();
      await expectLater(s.restoreFromBackup(account: kit.account, password: AppServices.newBackupPassword()), throwsA(isA<VaultAuthenticationFailed>()));
      expect(s.restoreInterrupted, isTrue);
      await s.restoreFromBackup(account: kit.account, password: kit.password);
      await expectWhole(s);
    });

    test('the patient can start fresh instead, with nothing left over', () async {
      final (_, s) = await interrupted();
      await s.createProfile(name: 'New Person', dob: DateTime(1990), sex: Sex.male);
      expect(s.restoreInterrupted, isFalse);
      expect(s.familyOnPhone().map((p) => p.name), ['New Person']);
      expect(s.repository.patients, hasLength(1));
      expect(s.backupAccount, isNull);
    });

    test('a different backup leaves nothing of the first', () async {
      final (_, s) = await interrupted();
      final other = await open(InMemoryByteStore(), key: 5);
      await other.createProfile(name: 'Someone Else', dob: DateTime(1990), sex: Sex.male, demo: false);
      final second = await other.setUpBackup();
      await s.restoreFromBackup(account: second.account, password: second.password);
      expect(s.repository.patients.map((p) => p.name), ['Someone Else']);
      expect(await s.attachments.load('a1'), isEmpty);
    });

    test('nothing treats the part-restored people as a family meanwhile', () async {
      final (disk, _) = await interrupted();
      final watched = await AppServices.open(
        bytes: disk,
        deviceKey: SecretKey(List.filled(32, 2)),
        remote: server,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        share: const ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        relayOverride: (_) => InMemoryRelay(),
        idDirectoryOverride: () => dir,
        retryAfter: null,
      );
      await watched.assignLifeTrackIds();
      expect(dir.entries, isEmpty, reason: 'no new ID for someone whose own is still in the backup');
      expect(watched.selfPatientId, isNull);
    });
  });

  test('a phone left half-restored by an older version, with no marker, can retry too', () async {
    final disk = InMemoryByteStore();
    final s = await open(disk);
    await s.restoreFromBackup(account: kit.account, password: kit.password);
    // What the old order left on disk when it died before the settings write.
    s.settings
      ..remove('currentPatientId')
      ..remove('selfPatientId');
    await s.setThemeChoice('system');
    final stuck = await open(disk);
    expect(stuck.currentPatient, isNull);
    await stuck.restoreFromBackup(account: kit.account, password: kit.password);
    await expectWhole(stuck);
  });

  test('a finished phone still refuses a restore', () async {
    final s = await open(InMemoryByteStore());
    await s.restoreFromBackup(account: kit.account, password: kit.password);
    await expectLater(s.restoreFromBackup(account: kit.account, password: kit.password), throwsA(isA<CustodyRefused>()));
    expect(s.audit.entriesFor(s.selfPatientId!).first.action, AuditAction.vaultRestore);
  });

  testWidgets('the welcome screen offers the retry', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      final disk = InMemoryByteStore();
      final dying = await open(DyingStore(disk, dieAfter: 14));
      try {
        await dying.restoreFromBackup(account: kit.account, password: kit.password);
      } on StateError {
        // The kill.
      }
      s = await open(disk);
    });
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not finish'), findsOneWidget);
    final button = find.textContaining('used LifeTrack before');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Bring back your records'), findsOneWidget);
    expect(find.textContaining('The last restore did not finish'), findsOneWidget);
    expect(find.widgetWithText(TextField, kit.account), findsOneWidget, reason: 'the account code is filled in');
  });
}
