import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A clinical share sealed to one doctor device, or a prescription sealed back
/// to one patient's reply key (CLAUDE.md #1b).
///
/// X25519 with a fresh ephemeral key per share → HKDF-SHA256 → AES-256-GCM.
/// Mirrors the shape of ABDM's ECDH-Curve25519 exchange so moving to the
/// ABDM health-information exchange later swaps the transport, not the crypto.
/// The relay that carries it holds no key that opens it.
abstract final class ShareEnvelope {
  static const version = 1;
  static final _x = X25519();
  static final _aead = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static List<int> _info(String keyId, String grantId) => utf8.encode('lifetrack/v1/clinical-share|$keyId|$grantId');

  static Future<Uint8List> seal({
    required Map<String, Object?> bundle,
    required List<int> recipientKey,
    required String keyId,
    required String grantId,
    required DateTime expiresAt,
  }) async {
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey();
    final shared = await _x.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(recipientKey, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(secretKey: shared, nonce: ephPub.bytes, info: _info(keyId, grantId));
    // The routing fields are bound into the ciphertext as associated data,
    // so a relay cannot re-address a share to another grant or expiry.
    final header = {'v': version, 'kid': keyId, 'gid': grantId, 'exp': expiresAt.toUtc().toIso8601String()};
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(bundle)),
      secretKey: key,
      aad: utf8.encode(jsonEncode(header)),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode({
      ...header,
      'eph': base64Encode(ephPub.bytes),
      'n': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    })));
  }

  /// Doctor side: opens a share with the device's X25519 key pair. Refuses an
  /// expired share even if the relay failed to delete it.
  static Future<Map<String, Object?>> open(Uint8List envelope, SimpleKeyPair doctorKeyPair, DateTime at) async {
    // doctorKeyPair: whichever X25519 pair the envelope was sealed to.
    final j = (jsonDecode(utf8.decode(envelope)) as Map).cast<String, Object?>();
    if (j['v'] != version) throw const FormatException('Unknown share version.');
    final expires = DateTime.parse(j['exp']! as String);
    if (!at.isBefore(expires)) throw const ShareExpired();
    final header = {'v': j['v'], 'kid': j['kid'], 'gid': j['gid'], 'exp': j['exp']};
    final ephPub = base64Decode(j['eph']! as String);
    final shared = await _x.sharedSecretKey(
      keyPair: doctorKeyPair,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(secretKey: shared, nonce: ephPub, info: _info(j['kid']! as String, j['gid']! as String));
    final plain = await _aead.decrypt(
      SecretBox(base64Decode(j['ct']! as String), nonce: base64Decode(j['n']! as String), mac: Mac(base64Decode(j['mac']! as String))),
      secretKey: key,
      aad: utf8.encode(jsonEncode(header)),
    );
    return (jsonDecode(utf8.decode(plain)) as Map).cast();
  }
}

class ShareExpired implements Exception {
  const ShareExpired();
}
