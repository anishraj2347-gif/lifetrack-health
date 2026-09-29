import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/shamir.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';

void main() {
  final key = SecretKey(List.filled(32, 7));

  group('VaultCodec framing', () {
    test('round-trips a body', () async {
      final frame = await VaultCodec.seal({'a': 1}, key);
      expect(frame.sublist(0, 3), [0x4C, 0x54, VaultCodec.frameVersion]);
      expect(await VaultCodec.open(frame, key), {'a': 1});
    });

    test('a frame without the magic is refused as unknown, not as corrupt', () async {
      final frame = await VaultCodec.seal('x', key);
      frame[0] = 0;
      expect(() => VaultCodec.open(frame, key), throwsA(isA<VaultFormatUnknown>()));
    });

    test('a newer frame version is refused before any decryption', () async {
      final frame = await VaultCodec.seal('x', key);
      frame[2] = VaultCodec.frameVersion + 1;
      expect(() => VaultCodec.open(frame, key), throwsA(isA<VaultFormatTooNew>()));
    });

    test('a newer schema inside a valid frame is refused', () async {
      final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode({'schemaVersion': 99, 'body': 1})), secretKey: key);
      final frame = Uint8List.fromList([0x4C, 0x54, 1, ...box.nonce, ...box.mac.bytes, ...box.cipherText]);
      expect(() => VaultCodec.open(frame, key), throwsA(isA<VaultFormatTooNew>()));
    });

    test('schema 0 (a bare list) is still readable', () async {
      final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode([1, 2])), secretKey: key);
      final frame = Uint8List.fromList([0x4C, 0x54, 1, ...box.nonce, ...box.mac.bytes, ...box.cipherText]);
      expect(await VaultCodec.open(frame, key), [1, 2]);
    });

    test('wrong key and tampering both fail authentication', () async {
      final frame = await VaultCodec.seal('secret', key);
      expect(() => VaultCodec.open(frame, SecretKey(List.filled(32, 8))), throwsA(isA<VaultAuthenticationFailed>()));
      frame[frame.length - 1] ^= 1;
      expect(() => VaultCodec.open(frame, key), throwsA(isA<VaultAuthenticationFailed>()));
    });

    test('the plaintext does not appear in the frame', () async {
      final frame = await VaultCodec.seal('Anjali Sharma', key);
      expect(latin1.decode(frame, allowInvalid: true).contains('Anjali'), isFalse);
    });
  });

  group('Key derivation', () {
    test('vault key and login verifier are distinct and deterministic', () async {
      final salt = List.filled(16, 1);
      final a = await VaultKeyDerivation.derive('correct horse', salt, KdfParams.weakForTests());
      final b = await VaultKeyDerivation.derive('correct horse', salt, KdfParams.weakForTests());
      final vaultA = await a.vaultKey.extractBytes();
      expect(vaultA, isNot(a.loginVerifier));
      expect(vaultA, await b.vaultKey.extractBytes());
      expect(a.loginVerifier, b.loginVerifier);
    });

    test('a different passphrase gives a different verifier', () async {
      final salt = List.filled(16, 1);
      final a = await VaultKeyDerivation.derive('one', salt, KdfParams.weakForTests());
      final b = await VaultKeyDerivation.derive('two', salt, KdfParams.weakForTests());
      expect(a.loginVerifier, isNot(b.loginVerifier));
    });
  });

  group('Shamir 2-of-3', () {
    final secret = List<int>.generate(32, (i) => i * 7 % 256);

    test('any two shares recover the secret', () {
      final s = Shamir.split(secret, threshold: 2, count: 3);
      expect(Shamir.combine([s[0], s[1]]), secret);
      expect(Shamir.combine([s[0], s[2]]), secret);
      expect(Shamir.combine([s[2], s[1]]), secret);
    });

    test('one share is refused rather than returning wrong bytes', () {
      final s = Shamir.split(secret, threshold: 2, count: 3);
      expect(() => Shamir.combine([s[0]]), throwsArgumentError);
    });

    test('duplicate and mixed shares are refused', () {
      final s = Shamir.split(secret, threshold: 2, count: 3);
      final t = Shamir.split(secret, threshold: 2, count: 3);
      expect(() => Shamir.combine([s[0], s[0]]), throwsArgumentError);
      expect(() => Shamir.combine([s[0], t[1]]), throwsArgumentError);
    });

    test('a printed share survives encode and decode', () {
      final s = Shamir.split(secret, threshold: 2, count: 3);
      expect(Shamir.combine([Share.decode(s[1].encode()), s[2]]), secret);
    });

    test('index zero is rejected', () {
      expect(() => Share(index: 0, threshold: 2, splitId: 'x', bytes: [1]), throwsArgumentError);
    });
  });
}
