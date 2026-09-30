import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  var now = DateTime(2026, 9, 30, 10);
  late InMemoryByteStore bytes;

  Future<AppServices> open() => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, 3)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );

  Future<AppServices> withOwner() async {
    final s = await open();
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984, 6, 14), sex: Sex.female);
    return s;
  }

  setUp(() {
    now = DateTime(2026, 9, 30, 10);
    bytes = InMemoryByteStore();
  });

  test("the owner's own profile is recorded as self", () async {
    final s = await withOwner();
    expect(s.familyOnPhone().map((p) => p.name), ['Anjali Sharma']);
    expect(s.custodyOf(s.selfPatientId!)!.kind, CustodyKind.self);
    expect(s.actingGrantor(), Actors.patient(s.selfPatientId!));
  });

  group('a child', () {
    test('is kept with the parent as guardian, and the parent grants for them', () async {
      final s = await withOwner();
      final child = await s.addChild(name: 'Aarav Sharma', dob: DateTime(2019, 2, 3), sex: Sex.male, relation: 'son');
      expect(s.familyOnPhone().map((p) => p.name), ['Anjali Sharma', 'Aarav Sharma']);
      final c = s.custodyOf(child.id)!;
      expect(c.kind, CustodyKind.childOfParent);
      expect(c.method, ConsentMethod.parentDeclaration);
      expect(c.isVerified, isFalse, reason: 'no verification service is connected; the app must not claim one');
      await s.switchTo(child.id);
      expect(s.currentPatient!.name, 'Aarav Sharma');
      expect(s.actingGrantor(), Actors.patient(s.selfPatientId!));
      expect(s.audit.entriesFor(child.id).single.detail, contains('(parent)'));
    });

    test('an adult cannot be added as a child', () async {
      final s = await withOwner();
      await expectLater(s.addChild(name: 'X', dob: DateTime(2000), sex: Sex.male, relation: 'son'), throwsA(isA<CustodyRefused>()));
    });

    test('at 18, the parent can no longer share on their behalf', () async {
      final s = await withOwner();
      final child = await s.addChild(name: 'Riya', dob: DateTime(2008, 10, 15), sex: Sex.female, relation: 'daughter');
      await s.switchTo(child.id);
      expect(s.actingGrantor(), isNotNull);
      now = DateTime(2026, 10, 16);
      expect(() => s.actingGrantor(), throwsA(isA<CustodyRefused>()));
      await expectLater(s.enableInsights(), throwsA(isA<CustodyRefused>()));
    });
  });

  group('an adult who asks to be managed', () {
    test('must confirm by typing their own name; the exact statement is kept', () async {
      final s = await withOwner();
      await expectLater(
        s.addDelegatingAdult(name: 'Ramesh Sharma', dob: DateTime(1955, 1, 1), sex: Sex.male, relation: 'father', typedName: 'Anjali Sharma'),
        throwsA(isA<CustodyRefused>()),
      );
      final dad = await s.addDelegatingAdult(name: 'Ramesh Sharma', dob: DateTime(1955, 1, 1), sex: Sex.male, relation: 'father', typedName: '  ramesh   sharma ');
      final c = s.custodyOf(dad.id)!;
      expect(c.kind, CustodyKind.delegatedByAdult);
      expect(c.method, ConsentMethod.inPersonOnCustodianPhone);
      expect(c.statement, contains('I, Ramesh Sharma, ask Anjali Sharma'));
      expect(c.statement, contains('I can stop this at any time'));
      expect(s.audit.entriesFor(dad.id).single.actorId, Actors.patient(dad.id), reason: 'the consent is his, not hers');
    });

    test('a minor cannot delegate', () async {
      final s = await withOwner();
      await expectLater(
        s.addDelegatingAdult(name: 'Kid', dob: DateTime(2015), sex: Sex.male, relation: 'son', typedName: 'Kid'),
        throwsA(isA<CustodyRefused>()),
      );
    });

    test('ending it revokes live access at once and removes the profile from the family list', () async {
      final s = await withOwner();
      final dad = await s.addDelegatingAdult(name: 'Ramesh Sharma', dob: DateTime(1955, 1, 1), sex: Sex.male, relation: 'father', typedName: 'Ramesh Sharma');
      await s.switchTo(dad.id);
      await s.enableInsights();
      expect(s.consent.activeGrantsFor(dad.id, now), hasLength(1));
      await s.endDelegation(dad.id);
      expect(s.consent.activeGrantsFor(dad.id, now), isEmpty);
      expect(s.familyOnPhone().map((p) => p.name), ['Anjali Sharma']);
      expect(s.currentPatientId, s.selfPatientId, reason: 'switched back to the owner');
      expect(s.audit.entriesFor(dad.id).first.action, AuditAction.grantRevoked);
    });
  });

  test('the owner cannot erase themselves while family profiles are on the phone', () async {
    final s = await withOwner();
    final child = await s.addChild(name: 'Aarav', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    await expectLater(s.eraseProfile(account: 'a'), throwsA(isA<CustodyRefused>()));
    await s.switchTo(child.id);
    await s.eraseProfile(account: 'a');
    expect(s.currentPatientId, s.selfPatientId);
    expect(s.familyOnPhone(), hasLength(1));
    await s.eraseProfile(account: 'a');
    expect(s.currentPatient, isNull);
  });

  test('family survives a restart', () async {
    final s = await withOwner();
    final child = await s.addChild(name: 'Aarav', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    await s.switchTo(child.id);
    await s.flush();
    final again = await open();
    expect(again.familyOnPhone().map((p) => p.name), ['Anjali Sharma', 'Aarav']);
    expect(again.currentPatient!.name, 'Aarav');
    expect(again.custodyOf(child.id)!.kind, CustodyKind.childOfParent);
  });
}
