import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/screens/add_record_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

import '../support/offline.dart';

/// A backup service a test can hold up, break, or count.
class TestVault implements RemoteVaultStore {
  final inner = InMemoryRemoteVaultStore();
  Completer<void>? gate;
  Object? failing;
  int puts = 0;
  void Function()? onPut;

  @override
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier}) async {
    onPut?.call();
    final g = gate;
    if (g != null) await g.future;
    final f = failing;
    if (f != null) throw f;
    puts++;
    await inner.put(account, entry, currentVerifier: currentVerifier);
  }

  @override
  Future<List<int>?> salt(String account) => inner.salt(account);
  @override
  Future<(Uint8List, Uint8List)> open(String account, List<int> verifier) => inner.open(account, verifier);
  @override
  Future<Uint8List?> blob(String account) => inner.blob(account);
  @override
  Future<void> delete(String account, List<int> verifier) => inner.delete(account, verifier);
}

void main() {
  final now = DateTime(2026, 10, 1, 10);
  late TestVault vault;
  late InMemoryByteStore bytes;
  late RecoveryKit kit;

  Future<AppServices> open({Duration delay = const Duration(hours: 1), Duration? retryAfter, RemoteVaultStore? remote}) => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, 7)),
        remote: remote ?? vault,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        backgroundDelay: delay,
        retryAfter: retryAfter,
      );

  Future<AppServices> withBackup({Duration delay = const Duration(hours: 1), Duration? retryAfter}) async {
    final s = await open(delay: delay, retryAfter: retryAfter);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    kit = await s.setUpBackup();
    return s;
  }

  HealthRecord record(AppServices s, String id, {RecordKind kind = RecordKind.report, Dose? dose}) =>
      HealthRecord(id: id, patientId: s.selfPatientId!, kind: kind, title: 'Record $id', date: now, source: RecordSource.typedByPatient, dose: dose);

  setUp(() {
    vault = TestVault();
    bytes = InMemoryByteStore();
  });

  group('a save never depends on the network', () {
    test('it returns with the service hung for ever, and the record is on disk', () async {
      final s = await withBackup();
      vault.gate = Completer();
      await s.addRecord(record(s, 'r1')).timeout(const Duration(seconds: 2));
      final again = await open();
      expect(again.repository.recordsOf(s.selfPatientId!).map((r) => r.id), contains('r1'));
      expect(again.backupBehind, isTrue, reason: 'the wait is on disk too');
    });

    test('nor does the Emergency ID, a prescription, or a home reading wait for linked family', () async {
      final registry = await Ed25519().newKeyPair();
      final relay = SwitchableRelay();
      final phone = TestPhone(relay: relay, registry: registry, now: () => now);
      final me = await phone.open();
      await me.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final other = await TestPhone(relay: relay, registry: registry, now: () => now).open();
      await other.createProfile(name: 'Vikram Sharma', dob: DateTime(1982), sex: Sex.male);
      await me.joinFamily(code: (await other.createFamilyInvite()).encode(), shareEmergency: true, shareMedicines: true);
      await other.checkInbox();

      // A relay that never answers: any await on it would hang this test.
      final calls = relay.calls;
      relay.down = true;
      await me.addRecord(record(me, 'rx', kind: RecordKind.prescription, dose: const Dose(morning: 1, afternoon: 0, night: 0))).timeout(const Duration(seconds: 2));
      await me.saveEmergencyCard(me.selfPatientId!, const EmergencyCard(bloodType: 'B+')).timeout(const Duration(seconds: 2));
      expect(relay.calls, calls, reason: 'nothing tried the network during the save');

      await me.settle();
      expect(me.settings['familyBehind'], isTrue, reason: 'it failed, and stays marked for the retry');
      relay.down = false;
      await me.settle();
      expect(me.settings.containsKey('familyBehind'), isFalse);
      await other.checkInbox();
      expect((await other.links!.links()).single.theirEmergency!['blood'], 'B+');
    });
  });

  group('the background backup', () {
    test('a burst of saves makes one backup, shortly after the last', () async {
      final s = await withBackup(delay: const Duration(milliseconds: 60));
      final before = vault.puts;
      for (var i = 0; i < 5; i++) {
        await s.addRecord(record(s, 'r$i'));
      }
      expect(vault.puts, before, reason: 'none yet');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await s.settle();
      expect(vault.puts, before + 1);
      expect(s.backupBehind, isFalse);
    });

    test('a change made while a backup is on its way is not lost', () async {
      final s = await withBackup();
      await s.addRecord(record(s, 'r1'));
      vault.gate = Completer();
      final uploading = Completer<void>();
      vault.onPut = () {
        if (!uploading.isCompleted) uploading.complete();
      };
      final first = s.settle();
      await uploading.future;
      await s.addRecord(record(s, 'r2')); // after the snapshot was taken
      vault.gate!.complete();
      vault.gate = null;
      await first;
      expect(s.backupBehind, isTrue, reason: 'r2 is not in what just went');
      await s.settle();
      expect(s.backupBehind, isFalse);

      final fresh = await AppServices.open(bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 8)), remote: vault, kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now);
      await fresh.restoreFromBackup(account: kit.account, password: kit.password);
      expect(fresh.repository.recordsOf(fresh.selfPatientId!).map((r) => r.id), containsAll(['r1', 'r2']));
    });

    test('killed before it ran, the next start sends it', () async {
      final s = await withBackup();
      await s.addRecord(record(s, 'r1'));
      final before = vault.puts;
      final again = await open();
      await again.settle();
      expect(vault.puts, before + 1);
      expect(again.backupBehind, isFalse);
    });

    test('offline it fails where the patient can see it, keeps trying, and clears itself', () async {
      final s = await withBackup(retryAfter: const Duration(milliseconds: 20));
      vault.failing = const RelayUnavailable('Could not reach the backup service.');
      final told = <String?>[];
      s.backupProblem.addListener(() => told.add(s.backupProblem.value));

      await s.addRecord(record(s, 'r1'));
      await s.settle();
      expect(told.single, 'Could not reach the backup service.');
      expect(s.lastBackupError, isNotNull);
      expect((await open()).backupProblem.value, isNotNull, reason: 'a restart does not make it go away');

      vault.failing = null;
      for (var i = 0; i < 100 && s.backupBehind; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(s.backupBehind, isFalse, reason: 'the retry timer did this, with no new change');
      expect(s.lastBackupError, isNull);
      expect(s.backupProblem.value, isNull);
    });

    test('the attempt is logged before it leaves, and a failed one says so', () async {
      final s = await withBackup();
      await s.addRecord(record(s, 'r1'));
      vault.failing = const RelayUnavailable('Could not reach the backup service.');
      String? onRecord;
      vault.onPut = () => onRecord = s.auditEntries().first.detail;
      await s.settle();
      expect(onRecord, startsWith('backup sent:'));
      expect(s.auditEntries().first.detail, 'backup did not reach the service');
    });

    test('a backup on its way cannot land after an erasure and put the records back', () async {
      final s = await withBackup();
      await s.addRecord(record(s, 'r1'));
      vault.gate = Completer();
      final uploading = Completer<void>();
      vault.onPut = () {
        if (!uploading.isCompleted) uploading.complete();
      };
      final backup = s.settle();
      await uploading.future;

      final erasing = s.eraseProfile();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      vault.gate!.complete();
      vault.gate = null;
      await backup;
      await erasing;
      expect(vault.inner.isEmpty, isTrue);
    });

    test('nothing waits once backup is off', () async {
      final s = await open();
      await s.createProfile(name: 'Solo', dob: DateTime(1990), sex: Sex.male);
      await s.addRecord(record(s, 'r1'));
      expect(s.backupBehind, isFalse);
    });
  });

  group('over HTTP', () {
    final base = Uri.parse('http://127.0.0.1:8787');
    final entry = RemoteVaultEntry(salt: const [1], verifier: const [2], wrappedDataKey: Uint8List(1), blob: Uint8List(1));

    test('a 413 is reported as too large, not as "could not reach"', () async {
      final remote = HttpRemoteVaultStore(baseUrl: base, client: MockClient((_) async => http.Response('{"error":"Backup too large."}', 413)));
      await expectLater(remote.put('LT-AAAAA-BBBBB', entry), throwsA(isA<VaultTooLarge>()));

      await withBackup();
      final limited = await open(remote: _TooLarge(vault));
      await limited.addRecord(record(limited, 'r1'));
      await limited.settle();
      expect(limited.lastBackupError, contains('too large'));
      expect(limited.lastBackupError, isNot(contains('reach')));
      expect(limited.backupBehind, isTrue);
    });

    test('a refusal that is not about size names the code and does not claim the server is away', () async {
      final remote = HttpRemoteVaultStore(baseUrl: base, client: MockClient((_) async => http.Response('{}', 500)));
      await expectLater(remote.put('LT-AAAAA-BBBBB', entry), throwsA(isA<RelayUnavailable>().having((e) => e.message, 'message', contains('500'))));
    });

    test('what goes on the wire is the same JSON the server reads', () async {
      late http.Request seen;
      final remote = HttpRemoteVaultStore(baseUrl: base, client: MockClient((r) async {
        seen = r;
        return http.Response('{}', 201);
      }));
      await remote.put('LT-AAAAA-BBBBB', entry, currentVerifier: const [9]);
      expect(seen.method, 'PUT');
      expect(seen.headers['content-type'], startsWith('application/json'));
      expect(seen.body, contains('"wrappedDataKey"'));
    });

    group('a server that has gone quiet', () {
      const quick = NetTimeouts(quick: Duration(milliseconds: 10), share: Duration(milliseconds: 10), bulk: Duration(milliseconds: 10));
      final silent = MockClient((_) => Completer<http.Response>().future);

      test('cannot hold the relay', () async {
        final tokens = InMemoryWithdrawTokens();
        await tokens.put('g', 't');
        final c = HttpRelayClient(baseUrl: base, tokens: tokens, client: silent, timeouts: quick);
        final mb = 'd-${'a' * 64}';
        await expectLater(c.deposit(mailbox: mb, grantId: 'g', envelope: Uint8List(1), expiresAt: now), throwsA(isA<TimeoutException>()));
        await tokens.put('w', 't');
        await expectLater(c.withdraw(mailbox: mb, grantId: 'w'), throwsA(isA<TimeoutException>()));
        expect(await tokens.peek('w'), 't', reason: 'a timeout spends no token');
        await expectLater(c.collect(mailbox: mb, secret: 's'), throwsA(isA<TimeoutException>()));
      });

      test('cannot hold the backup', () async {
        final c = HttpRemoteVaultStore(baseUrl: base, client: silent, timeouts: quick);
        await expectLater(c.put('LT-AAAAA-BBBBB', entry), throwsA(isA<RelayUnavailable>()));
        await expectLater(c.salt('LT-AAAAA-BBBBB'), throwsA(isA<RelayUnavailable>()));
        await expectLater(c.open('LT-AAAAA-BBBBB', const [1]), throwsA(isA<RelayUnavailable>()));
        await expectLater(c.blob('LT-AAAAA-BBBBB'), throwsA(isA<RelayUnavailable>()));
        await expectLater(c.delete('LT-AAAAA-BBBBB', const [1]), throwsA(isA<RelayUnavailable>()));
      });

      test('cannot hold ID registration', () async {
        final c = HttpIdDirectory(baseUrl: base, client: silent, timeouts: quick);
        await expectLater(c.register(id: '1', mailbox: 'm', key: const [1], tokenHash: 'h'), throwsA(isA<TimeoutException>()));
        await expectLater(c.delete(id: '1', token: 't'), throwsA(isA<TimeoutException>()));
        await expectLater(c.move(id: '1', token: 't', mailbox: 'm', key: const [1]), throwsA(isA<TimeoutException>()));
      });

      test('reads as "offline" to the patient', () async {
        final c = HttpDoctorStatus(baseUrl: base, client: silent, timeouts: quick);
        final doctor = await TestDoctor.make(await Ed25519().newKeyPair());
        expect(await c.stillApproved(doctor.cert), isNull, reason: 'null: could not ask');
      });
    });
  });

  test('sealed off the screen, a backup opens like any other', () async {
    final key = SecretKey(List.filled(32, 3));
    final frame = await VaultCodec.sealOffScreen({'a': [1, 2, 3], 'b': 'text'}, key);
    expect(await VaultCodec.open(frame, key), {'a': [1, 2, 3], 'b': 'text'});
    expect(await VaultCodec.openOffScreen(frame, key), {'a': [1, 2, 3], 'b': 'text'});
    await expectLater(VaultCodec.openOffScreen(frame, SecretKey(List.filled(32, 4))), throwsA(isA<VaultAuthenticationFailed>()));
  });

  test('writes that overlap all reach the disk, in order', () async {
    final store = _SlowFirstWrite();
    final log = await PersistentAuditLog.open(SealedStore(store, SecretKey(List.filled(32, 2))));
    AuditEntry e(String d) => AuditEntry(at: now, actorId: 'patient:p', patientId: 'p', action: AuditAction.edit, detail: d);
    await Future.wait([log.append(e('one')), log.append(e('two')), log.append(e('three'))]);
    final back = await PersistentAuditLog.open(SealedStore(store, SecretKey(List.filled(32, 2))));
    expect(back.entriesFor('p').map((x) => x.detail), ['three', 'two', 'one']);
  });

  group('the Save button', () {
    Future<AppServices> pumpForm(WidgetTester tester) async {
      late AppServices s;
      await tester.runAsync(() async {
        s = await AppServices.open(bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(), kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now);
        await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      });
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const AddRecordScreen())), child: const Text('open'))))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type it in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Note').first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Felt dizzy');
      await tester.pump();
      return s;
    }

    testWidgets('a second tap saves nothing more', (tester) async {
      final s = await pumpForm(tester);
      final button = find.text('Save record');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false); // before any frame could disable it
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(s.repository.recordsOf(s.selfPatientId!).where((r) => r.title == 'Felt dizzy'), hasLength(1));
      expect(s.auditEntries().where((e) => (e.detail ?? '').startsWith('added')), hasLength(1));
    });
  });

  testWidgets('a backup that fails in the background tells the patient on whatever screen they are on', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await withBackup();
      await s.addRecord(record(s, 'r1'));
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    expect(find.textContaining('Backup failed'), findsNothing);

    vault.failing = const RelayUnavailable('Could not reach the backup service.');
    await tester.runAsync(s.settle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Backup failed. Could not reach the backup service.'), findsOneWidget);
  });
}

/// A service with a size limit.
class _TooLarge implements RemoteVaultStore {
  _TooLarge(this.inner);
  final RemoteVaultStore inner;
  @override
  Future<void> put(String account, RemoteVaultEntry entry, {List<int>? currentVerifier}) async => throw const VaultTooLarge();
  @override
  Future<List<int>?> salt(String account) => inner.salt(account);
  @override
  Future<(Uint8List, Uint8List)> open(String account, List<int> verifier) => inner.open(account, verifier);
  @override
  Future<Uint8List?> blob(String account) => inner.blob(account);
  @override
  Future<void> delete(String account, List<int> verifier) => inner.delete(account, verifier);
}

class _SlowFirstWrite extends InMemoryByteStore {
  var _n = 0;
  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (_n++ == 0) await Future<void>.delayed(const Duration(milliseconds: 30));
    await super.write(name, bytes);
  }
}

