import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/capture/profile_photo.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/custody.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Profile photos: small and clean, sealed, logged, backed up, erased.
void main() {
  final now = DateTime(2026, 10, 12, 10);
  late InMemoryRemoteVaultStore server;
  setUp(() => server = InMemoryRemoteVaultStore());

  Future<AppServices> phone(InMemoryByteStore bytes, int key) => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, key)),
        remote: server,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );

  test('a picked photo becomes a 320 px square JPEG without its metadata', () {
    final wide = img.Image(width: 900, height: 600)..exif.imageIfd['Make'] = 'Camera';
    final out = prepareProfilePhoto(img.encodeJpg(wide))!;
    final back = img.decodeJpg(out)!;
    expect((back.width, back.height), (320, 320));
    expect(back.exif.imageIfd['Make'], isNull);
    expect(prepareProfilePhoto(Uint8List.fromList([1, 2, 3])), isNull, reason: 'not an image');
  });

  test('stored sealed, kept across a restart, logged, in the backup, gone on erasure', () async {
    final bytes = InMemoryByteStore();
    final s = await phone(bytes, 1);
    final me = await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final child = await s.addChild(name: 'Aarav Sharma', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    final jpeg = prepareProfilePhoto(img.encodeJpg(img.Image(width: 400, height: 400)))!;
    await s.setPhoto(child.id, jpeg);

    // Nothing on disk holds the JPEG in the clear.
    for (final name in await bytes.names()) {
      final b = (await bytes.read(name))!;
      expect(_contains(b, jpeg.sublist(0, 64)), isFalse, reason: name);
    }
    expect(s.audit.entriesFor(child.id).any((e) => e.action == AuditAction.edit && e.detail == 'Profile photo changed'), isTrue);

    final reopened = await phone(bytes, 1);
    expect(reopened.photoOf(child.id), jpeg);
    expect(reopened.photoOf(me.id), isNull);

    final kit = await reopened.setUpBackup();
    final fresh = await phone(InMemoryByteStore(), 2);
    await fresh.restoreFromBackup(account: kit.account, password: kit.password);
    expect(fresh.photoOf(child.id), jpeg);

    await reopened.switchTo(child.id);
    await reopened.eraseProfile();
    expect(reopened.photoOf(child.id), isNull);
    expect(await reopened.attachments.load('photo-${child.id}').then((p) => p, onError: (_) => const <Uint8List>[]), isEmpty);
  });

  test('only someone on this phone can be given a photo', () async {
    final s = await phone(InMemoryByteStore(), 1);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    expect(() => s.setPhoto('p-not-here', Uint8List(4)), throwsA(isA<CustodyRefused>()));
  });
}

bool _contains(Uint8List hay, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
