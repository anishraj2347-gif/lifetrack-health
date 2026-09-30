import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/abha.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/screens/abha_screen.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  var now = DateTime(2026, 10, 1, 10);
  late InMemoryByteStore bytes;

  Future<AppServices> open() => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, 4)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );

  setUp(() {
    now = DateTime(2026, 10, 1, 10);
    bytes = InMemoryByteStore();
  });

  group('the number and address', () {
    test('14 digits, with or without dashes and spaces', () {
      expect(Abha.parseNumber('91-1234-5678-9012'), '91123456789012');
      expect(Abha.parseNumber(' 9112 3456 7890 12 '), '91123456789012');
      expect(Abha.parseNumber('9112345678901'), isNull);
      expect(Abha.parseNumber('9112345678901a'), isNull);
    });

    test('an address is name@domain', () {
      expect(Abha.parseAddress('Anjali.Sharma@ABDM'), 'anjali.sharma@abdm');
      expect(Abha.parseAddress('anjali@sbx'), 'anjali@sbx');
      expect(Abha.parseAddress('anjali'), isNull);
      expect(Abha.parseAddress('a@abdm'), isNull);
    });

    test('shown in full to its owner, and only the last four on the Emergency ID', () {
      final a = Abha(number: '91123456789012', addedAt: now);
      expect(a.display, '91-1234-5678-9012');
      expect(a.masked, 'XX-XXXX-XXXX-9012');
      expect(a.masked, isNot(contains('1234')));
    });
  });

  test('added by the owner, kept encrypted with the profile, never verified by assumption', () async {
    final s = await open();
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await expectLater(s.setAbha(number: '123'), throwsFormatException);
    await expectLater(s.setAbha(number: '91-1234-5678-9012', address: 'nope'), throwsFormatException);
    await s.setAbha(number: '91-1234-5678-9012', address: 'anjali.sharma@abdm');
    await s.flush();
    final again = await open();
    final a = again.currentPatient!.abha!;
    expect((a.number, a.address, a.verified), ('91123456789012', 'anjali.sharma@abdm', false));
    final log = again.audit.entriesFor(again.selfPatientId!).first;
    expect(log.action, AuditAction.edit);
    expect(log.detail, contains('XX-XXXX-XXXX-9012'));
    expect(log.detail, isNot(contains('1234')), reason: 'the full number is not copied into the log');
    await again.setAbha();
    expect(again.currentPatient!.abha, isNull);
  });

  test("a parent adds a child's ABHA, until the child is 18", () async {
    final s = await open();
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final child = await s.addChild(name: 'Riya', dob: DateTime(2008, 10, 15), sex: Sex.female, relation: 'daughter');
    await s.switchTo(child.id);
    await s.setAbha(number: '91000011112222');
    expect(s.currentPatient!.abha!.number, '91000011112222');
    now = DateTime(2026, 10, 16);
    await expectLater(s.setAbha(), throwsA(isA<CustodyRefused>()));
  });

  test('the registration QR carries identity and ABHA only', () {
    final j = jsonDecode(AbhaQrScreen.payload('Anjali Sharma', DateTime(1984, 6, 14), 'female', Abha(number: '91123456789012', addedAt: now))) as Map;
    expect(j.keys.toSet(), {'type', 'abhaNumber', 'name', 'dob', 'gender', 'verified'});
    expect(j['abhaNumber'], '91-1234-5678-9012');
    expect(j['verified'], false);
  });
}
