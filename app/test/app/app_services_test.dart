import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/shamir.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  var now = DateTime(2026, 4, 1, 9);
  final key = SecretKey(List.filled(32, 5));
  late InMemoryByteStore bytes;
  late InMemoryRemoteVaultStore remote;

  Future<AppServices> open() => AppServices.open(
        bytes: bytes,
        deviceKey: key,
        remote: remote,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );

  setUp(() {
    now = DateTime(2026, 4, 1, 9);
    bytes = InMemoryByteStore();
    remote = InMemoryRemoteVaultStore();
  });

  test('a new install starts empty; demo data is written only when chosen', () async {
    final s = await open();
    expect(s.currentPatient, isNull);
    final p = await s.createProfile(name: 'A', dob: DateTime(1990), sex: Sex.female);
    expect(s.records(), isEmpty);
    expect(p.name, 'A');
    expect(s.auditEntries(), isEmpty, reason: 'no fabricated history');
  });

  test('insights require the patient to turn them on, and every read is audited', () async {
    final s = await open();
    await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    expect(await s.runInsights(), isNull);
    await s.enableInsights();
    final run = (await s.runInsights())!;
    expect(run.insights, isNotEmpty);
    expect(run.unresolved.map((u) => u.analyte), contains('vitamin_d'));
    final views = s.auditEntries().where((e) => e.action == AuditAction.view);
    expect(views.map((e) => e.actorId).toSet(), {Actors.planeA});
  });

  test('the audit log, grants and records survive the process dying', () async {
    final s = await open();
    await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    final g = await s.grantDoctor(doctorRegistryId: 'NMC-7', scopes: {DataClass.reports}, window: const Duration(hours: 24), type: GrantType.session);
    await s.flush();

    final relaunched = await open();
    expect(relaunched.records(), hasLength(s.records().length));
    expect(relaunched.activeGrants().single.id, g.id);
    expect(relaunched.auditEntries().first.action, AuditAction.grantIssued);

    await relaunched.revoke(relaunched.activeGrants().single);
    await relaunched.flush();
    expect((await open()).activeGrants(), isEmpty);
  });

  test('expired grants are gone after a relaunch the next week', () async {
    final s = await open();
    await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    await s.grantDoctor(doctorRegistryId: 'NMC-7', scopes: {DataClass.reports}, window: const Duration(hours: 24), type: GrantType.session);
    await s.flush();
    now = now.add(const Duration(days: 7));
    final later = await open();
    expect(later.activeGrants(), isEmpty);
    await later.grantDoctor(doctorRegistryId: 'NMC-7', scopes: {DataClass.reports}, window: const Duration(hours: 24), type: GrantType.session);
    expect(later.activeGrants(), hasLength(1));
  });

  test('Plane C is dark: confirming a disclosure is refused and nothing is sent', () async {
    final s = await open();
    final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    expect(s.cloud.isAvailable(now), isFalse);
    final d = s.cloud.prepare(p.id, now);
    final outcome = await s.cloud.confirm(d, now);
    expect(outcome.refusal, isNotNull);
    expect(s.auditEntries().where((e) => e.action == AuditAction.cloudEgress), isEmpty);
    expect(s.activeGrants().where((g) => g.grantedToActorId == Actors.cloud), isEmpty, reason: 'the unused cloud grant is revoked');
  });

  group('backup vault', () {
    test('restores with the passphrase or any two shares; notes stay local', () async {
      final s = await open();
      final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
      await s.addRecord(HealthRecord(id: 'note1', patientId: p.id, kind: RecordKind.note, title: 'Felt dizzy', date: now, source: RecordSource.typedByPatient));
      final setup = await s.vault.create(account: '+919800000047', patientId: p.id, passphrase: 'six unrelated words go here ok', records: s.records(), at: now);
      final salt = (await s.vault.saltFor('+919800000047'))!;

      final viaPhrase = await s.vault.restoreWithPassphrase(account: '+919800000047', patientId: p.id, passphrase: 'six unrelated words go here ok', salt: salt, at: now);
      expect(viaPhrase.where((r) => r.kind == RecordKind.note), isEmpty);
      expect(viaPhrase, hasLength(s.records().length - 1));
      expect(viaPhrase.every((r) => r.source == RecordSource.restoredFromBackup), isTrue);

      final viaShares = await s.vault.restoreWithShares(account: '+919800000047', patientId: p.id, shares: [setup.shares[1], setup.shares[2]], at: now);
      expect(viaShares.length, viaPhrase.length);
      expect(() => s.vault.restoreWithShares(account: '+919800000047', patientId: p.id, shares: [setup.shares[0]], at: now), throwsArgumentError);

      expect(s.auditEntries().where((e) => e.action == AuditAction.vaultRestore), hasLength(2));
    });

    test('a wrong passphrase is refused', () async {
      final s = await open();
      final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
      await s.vault.create(account: 'acct', patientId: p.id, passphrase: 'right', records: s.records(), at: now);
      final salt = (await s.vault.saltFor('acct'))!;
      await expectLater(
        s.vault.restoreWithPassphrase(account: 'acct', patientId: p.id, passphrase: 'wrong', salt: salt, at: now),
        throwsA(isA<VaultAuthenticationFailed>()),
      );
    });

    test('shares are printable and LifeTrack keeps none', () async {
      final s = await open();
      final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
      final setup = await s.vault.create(account: 'acct', patientId: p.id, passphrase: 'x', records: s.records(), at: now);
      expect(setup.shares, hasLength(3));
      expect(Share.decode(setup.shares.first.encode()).index, 1);
    });
  });

  test('erasure removes records, grants, the Emergency ID and the backup', () async {
    final s = await open();
    final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    await s.emergency.save(p.id, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    await s.grantDoctor(doctorRegistryId: 'NMC-7', scopes: {DataClass.reports}, window: const Duration(hours: 24), type: GrantType.session);
    await s.vault.create(account: 'acct', patientId: p.id, passphrase: 'x', records: s.records(), at: now);

    await s.eraseProfile(account: 'acct');

    expect(s.currentPatient, isNull);
    expect(s.repository.recordsOf(p.id), isEmpty);
    expect(s.consent.activeGrantsFor(p.id, now), isEmpty);
    expect((await s.emergency.load(p.id)).isEmpty, isTrue);
    expect(remote.isEmpty, isTrue);
    final log = s.audit.entriesFor(p.id);
    expect(log.single.action, AuditAction.erasure);

    final relaunched = await open();
    expect(relaunched.currentPatient, isNull);
    expect(relaunched.repository.recordsOf(p.id), isEmpty);
  });

  group('Emergency ID', () {
    test('a lock-screen read is audited', () async {
      final s = await open();
      final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
      await s.emergency.save(p.id, const EmergencyCard(bloodType: 'B+'));
      final card = await s.emergency.readFromLockScreen(p.id, now);
      expect(card.bloodType, 'B+');
      expect(s.auditEntries().first.action, AuditAction.emergencyRead);
    });

    test('hygiene rules are enforced on save', () async {
      final s = await open();
      final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
      expect(() => s.emergency.save(p.id, const EmergencyCard(bloodType: 'Q')), throwsArgumentError);
      expect(() => s.emergency.save(p.id, EmergencyCard(allergies: 'x' * 500)), throwsArgumentError);
      expect(() => s.emergency.save(p.id, const EmergencyCard(contactPhone: 'call me')), throwsArgumentError);
    });
  });
}
