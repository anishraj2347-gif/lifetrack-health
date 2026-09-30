import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
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
    await s.enableInsights();
    final g = s.activeGrants().single;
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
    await s.enableInsights();
    await s.flush();
    now = now.add(const Duration(days: 7));
    final later = await open();
    expect(later.activeGrants(), isEmpty);
    await later.enableInsights();
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

  test('erasure removes records, grants, the Emergency ID and the backup', () async {
    final s = await open();
    final p = await s.createProfile(name: '', dob: DateTime(1984), sex: Sex.female, demo: true);
    await s.emergency.save(p.id, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    await s.enableInsights();
    await s.setUpBackup();
    expect(remote.isEmpty, isFalse);

    await s.eraseProfile();

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
      expect(const EmergencyCard(contactPhone: '161').validate().single, contains('too short'));
      expect(const EmergencyCard(contactPhone: '+91 98765 43210').validate(), isEmpty);
    });
  });
}
