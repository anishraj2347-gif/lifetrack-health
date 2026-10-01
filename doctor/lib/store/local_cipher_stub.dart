import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_cipher.dart';
import 'memory_cipher.dart';

/// Phones (Android/iOS): the AES-256 key lives in the platform keystore
/// (Android Keystore-wrapped storage / iOS Keychain, this device only), so
/// what the app keeps in its preferences is ciphertext.
LocalCipher createCipher() => KeystoreCipher();

class KeystoreCipher implements LocalCipher {
  static const _name = 'lifetrack.doctor.local_key.v1';
  final _storage = const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
  Future<MemoryCipher>? _inner;

  Future<MemoryCipher> _cipher() => _inner ??= () async {
        var b64 = await _storage.read(key: _name);
        if (b64 == null) {
          final r = Random.secure();
          b64 = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
          await _storage.write(key: _name, value: b64);
        }
        return MemoryCipher(SecretKey(base64Decode(b64)));
      }();

  @override
  Future<String> seal(String plain) async => (await _cipher()).seal(plain);

  @override
  Future<String> open(String sealed) async => (await _cipher()).open(sealed);

  @override
  Future<void> reset() async {
    await _storage.delete(key: _name);
    _inner = null;
  }
}
