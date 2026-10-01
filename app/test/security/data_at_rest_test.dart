import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/security/plain_leftovers.dart';
import 'package:lifetrack/src/security/screen_privacy.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// What sits on the phone's storage, and in files the app hands out, is
/// ciphertext unless the patient chose otherwise.
void main() {
  final now = DateTime(2026, 10, 1, 10);

  Future<(AppServices, InMemoryByteStore)> open({bool demo = false, ScreenPrivacy? privacy, InMemoryByteStore? bytes}) async {
    final b = bytes ?? InMemoryByteStore();
    final s = await AppServices.open(
      bytes: b, deviceKey: SecretKey(List.filled(32, 4)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now, demoTools: demo, screenPrivacy: privacy,
    );
    return (s, b);
  }

  bool containsText(Uint8List? raw, String text) => raw != null && latin1.decode(raw, allowInvalid: true).contains(text);

  test('every blob on disk is sealed: no name, value or card field in the clear', () async {
    final (s, bytes) = await open();
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.saveEmergencyCard(me.id, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin', contactPhone: '+91 98765 43210'));
    await s.addRecord(HealthRecord(id: 'r1', patientId: me.id, kind: RecordKind.report, title: 'Lipid panel', date: now, source: RecordSource.typedByPatient,
        results: const [LabResult(analyte: 'ldl', value: 132, unit: 'mg/dL')]));
    final names = await bytes.names();
    expect(names, isNotEmpty);
    for (final n in names) {
      final raw = await bytes.read(n);
      for (final secret in ['Anjali', 'Penicillin', '98765', 'Lipid', '"ldl"']) {
        expect(containsText(raw, secret), isFalse, reason: '$secret readable in $n');
      }
    }
    expect((await s.emergency.load(me.id)).allergies, 'Penicillin', reason: 'still readable by the app');
  });

  test('an Emergency ID saved in the clear by an older version is sealed on first read', () async {
    final bytes = InMemoryByteStore();
    final (s0, _) = await open(bytes: bytes);
    final me = await s0.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final blob = 'emergency_card_${me.id}';
    await bytes.write(blob, Uint8List.fromList(utf8.encode(jsonEncode(const EmergencyCard(bloodType: 'O+', allergies: 'Sulfa').toJson()))));
    expect(containsText(await bytes.read(blob), 'Sulfa'), isTrue, reason: 'the old plain format');

    final card = await s0.emergency.readFromLockScreen(me.id, now);
    expect(card.allergies, 'Sulfa');
    expect(containsText(await bytes.read(blob), 'Sulfa'), isFalse, reason: 'sealed now');
    expect((await s0.emergency.load(me.id)).bloodType, 'O+');
  });

  test('export with a password: every file AES-encrypted, opens only with it', () async {
    final (s, _) = await open();
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.addRecord(HealthRecord(id: 'r1', patientId: me.id, kind: RecordKind.note, title: 'Felt dizzy', date: now, source: RecordSource.typedByPatient));
    final e = await s.exportCurrent();
    final pw = AppServices.newBackupPassword();
    final zip = e.zip(password: pw);
    expect(containsText(zip, 'Felt dizzy'), isFalse);
    expect(containsText(zip, 'Anjali'), isFalse);
    final opened = ZipDecoder().decodeBytes(zip, password: pw);
    expect(utf8.decode(opened.findFile('records.json')!.content as List<int>), contains('Felt dizzy'));
    Object? wrong;
    try {
      final bad = ZipDecoder().decodeBytes(zip, password: AppServices.newBackupPassword());
      final text = utf8.decode(bad.findFile('records.json')!.content as List<int>, allowMalformed: true);
      if (!text.contains('Felt dizzy')) wrong = 'unreadable';
    } on Object catch (x) {
      wrong = x;
    }
    expect(wrong, isNotNull, reason: 'a wrong password does not open it');
    expect(utf8.decode(ZipDecoder().decodeBytes(e.zip()).findFile('records.json')!.content as List<int>), contains('Felt dizzy'),
        reason: 'without a password the patient chose a plain file');
  });

  group('screen privacy', () {
    test('on by default and applied at start; demo builds start off; changes are logged', () async {
      final p = RecordingScreenPrivacy();
      final (s, _) = await open(privacy: p);
      await Future<void>.delayed(Duration.zero);
      expect(s.screenPrivacyEnabled, isTrue);
      expect(p.on, isTrue);
      final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.setScreenPrivacy(false);
      expect(p.on, isFalse);
      expect(s.audit.entriesFor(me.id).map((e) => e.detail), contains('Screen privacy turned off'));

      final d = RecordingScreenPrivacy();
      final (demo, _) = await open(demo: true, privacy: d);
      await Future<void>.delayed(Duration.zero);
      expect(demo.screenPrivacyEnabled, isFalse);
      expect(d.on, isFalse);
    });

    test('the choice survives a restart', () async {
      final bytes = InMemoryByteStore();
      final (s, _) = await open(bytes: bytes);
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.setScreenPrivacy(false);
      final p = RecordingScreenPrivacy();
      final (again, _) = await open(bytes: bytes, privacy: p);
      await Future<void>.delayed(Duration.zero);
      expect(again.screenPrivacyEnabled, isFalse);
      expect(p.on, isFalse);
    });
  });

  test('plain leftovers in the cache are swept; nothing else is touched', () async {
    final dir = await Directory.systemTemp.createTemp('lt-cache');
    addTearDown(() => dir.delete(recursive: true));
    for (final n in ['image_picker_1234.jpg', 'lab-report.pdf', 'lifetrack-anjali-2026-10-01.zip', 'emergency-id.png', 'keep.txt', 'flutter_engine.bin']) {
      await File('${dir.path}/$n').writeAsString('x');
    }
    await Directory('${dir.path}/share_plus').create();
    await File('${dir.path}/share_plus/copy.zip').writeAsString('x');
    await Directory('${dir.path}/other').create();

    expect(await sweepPlainLeftovers(dir), 5);
    final left = [await for (final e in dir.list()) e.uri.pathSegments.where((x) => x.isNotEmpty).last]..sort();
    expect(left, ['flutter_engine.bin', 'keep.txt', 'other']);

    final one = File('${dir.path}/image_picker_x.jpg');
    await one.writeAsString('x');
    await deleteQuietly(one.path);
    expect(await one.exists(), isFalse);
    await deleteQuietly('${dir.path}/never-existed.jpg');
  });

  test('the audit log on disk is sealed too', () async {
    final (s, bytes) = await open();
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.setScreenPrivacy(true);
    expect(s.audit.entriesFor(me.id).any((e) => e.action == AuditAction.edit), isTrue);
    for (final n in await bytes.names()) {
      expect(containsText(await bytes.read(n), 'Screen privacy'), isFalse, reason: n);
    }
  });
}
