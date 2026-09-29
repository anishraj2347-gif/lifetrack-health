import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the key that encrypts records at rest on this phone.
abstract interface class DeviceKeyStore {
  /// Returns the device key, creating it on first use.
  Future<SecretKey> deviceKey();

  /// Destroys the key. Everything encrypted under it becomes unreadable —
  /// this is what makes on-device erasure final.
  Future<void> destroy();
}

/// Android Keystore / iOS Keychain via `flutter_secure_storage`.
///
/// iOS: `first_unlock_this_device` — never migrates to another device through
/// a backup. Android: stored in EncryptedSharedPreferences under a
/// Keystore-held master key.
class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  static const _name = 'lifetrack.device_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SecretKey> deviceKey() async {
    final existing = await _storage.read(key: _name);
    if (existing != null) return SecretKey(base64Decode(existing));
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    await _storage.write(key: _name, value: base64Encode(bytes));
    return SecretKey(bytes);
  }

  @override
  Future<void> destroy() => _storage.delete(key: _name);
}
