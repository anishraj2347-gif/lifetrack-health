import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// On-disk frame: `magic('LT') ‖ version ‖ nonce(12) ‖ mac(16) ‖ ciphertext`,
/// AES-256-GCM. The plaintext is a JSON envelope `{schemaVersion, body}`.
///
/// The magic matters: a bare version byte is indistinguishable from a nonce
/// that happens to start with the same value. A frame from a *newer* app is
/// refused with [VaultFormatTooNew] rather than sliced at fixed offsets —
/// misparsing would surface as an authentication failure, which reads to a
/// patient as "your records are corrupt", which is what makes them delete them.
abstract final class VaultCodec {
  static const magic = [0x4C, 0x54]; // 'L', 'T'
  static const frameVersion = 1;
  static const schemaVersion = 1;
  static const _nonceLen = 12;
  static const _macLen = 16;
  static const _headerLen = 2 + 1 + _nonceLen + _macLen;

  static final _aead = AesGcm.with256bits();

  static Future<Uint8List> seal(Object? body, SecretKey key) async {
    final plain = utf8.encode(jsonEncode({'schemaVersion': schemaVersion, 'body': body}));
    final box = await _aead.encrypt(plain, secretKey: key);
    return Uint8List.fromList([
      ...magic,
      frameVersion,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  static Future<Object?> open(Uint8List frame, SecretKey key) async {
    if (frame.length < _headerLen || frame[0] != magic[0] || frame[1] != magic[1]) {
      throw const VaultFormatUnknown();
    }
    final version = frame[2];
    if (version > frameVersion) throw VaultFormatTooNew(version);
    final nonce = frame.sublist(3, 3 + _nonceLen);
    final mac = frame.sublist(3 + _nonceLen, _headerLen);
    final cipher = frame.sublist(_headerLen);
    final List<int> plain;
    try {
      plain = await _aead.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const VaultAuthenticationFailed();
    }
    final decoded = jsonDecode(utf8.decode(plain));
    // Schema 0 was a bare list with no envelope; still readable.
    if (decoded is List) return decoded;
    final env = (decoded as Map).cast<String, Object?>();
    final schema = env['schemaVersion'] as int? ?? 0;
    if (schema > schemaVersion) throw VaultFormatTooNew(schema);
    return env['body'];
  }
}

sealed class VaultError implements Exception {
  const VaultError();
  String get patientMessage;
}

class VaultFormatUnknown extends VaultError {
  const VaultFormatUnknown();
  @override
  String get patientMessage => 'This file was not written by LifeTrack.';
}

class VaultFormatTooNew extends VaultError {
  const VaultFormatTooNew(this.version);
  final int version;
  @override
  String get patientMessage =>
      'These records were saved by a newer version of LifeTrack. Update the app to open them. Nothing has been changed.';
}

class VaultAuthenticationFailed extends VaultError {
  const VaultAuthenticationFailed();
  @override
  String get patientMessage => 'The key does not match these records, or the file was altered.';
}
