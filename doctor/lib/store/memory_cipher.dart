import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'local_cipher.dart';

/// AES-256-GCM with a key held in memory — tests, and anywhere without
/// WebCrypto. Same 'lt1:' format as the browser's.
class MemoryCipher implements LocalCipher {
  MemoryCipher([SecretKey? key]) : _key = key ?? SecretKey(List<int>.generate(32, (i) => (i * 37 + 11) % 256));
  SecretKey _key;
  final _aes = AesGcm.with256bits();

  @override
  Future<String> seal(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _key);
    return '${LocalCipher.prefix}${base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes])}';
  }

  @override
  Future<String> open(String sealed) async {
    if (!sealed.startsWith(LocalCipher.prefix)) throw const FormatException('not sealed');
    final b = base64Decode(sealed.substring(LocalCipher.prefix.length));
    final box = SecretBox(b.sublist(12, b.length - 16), nonce: b.sublist(0, 12), mac: Mac(b.sublist(b.length - 16)));
    return utf8.decode(await _aes.decrypt(box, secretKey: _key));
  }

  @override
  Future<void> reset() async => _key = await _aes.newSecretKey();
}
