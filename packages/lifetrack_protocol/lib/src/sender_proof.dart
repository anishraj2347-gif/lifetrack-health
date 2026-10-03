import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Proves that a clinical share came from the phone that holds the reply
/// key it names — not just from someone who looked that key up.
///
/// The registry's ID lookup is public, so "the LifeTrack ID is registered to
/// this reply key" proves nothing on its own: anyone can copy both into a
/// share. The proof is an HMAC under a key from X25519(reply key, doctor's
/// encryption key). Only the patient's phone (reply private key) and the
/// doctor's device (encryption private key) can compute it, and it is bound
/// to the grant, the ID and the reply key, so it cannot be moved to another.
abstract final class SenderProof {
  static final _x = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _hmac = Hmac.sha256();

  static List<int> _message(String grantId, String lifeTrackId, List<int> replyKey) =>
      utf8.encode('lifetrack/v1/share-sender|$grantId|$lifeTrackId|${base64Encode(replyKey)}');

  static Future<List<int>> _mac(SimpleKeyPair mine, List<int> theirs, String grantId, String lifeTrackId, List<int> replyKey) async {
    final shared = await _x.sharedSecretKey(keyPair: mine, remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519));
    final key = await _hkdf.deriveKey(secretKey: shared, nonce: const [], info: utf8.encode('lifetrack/v1/share-sender'));
    return (await _hmac.calculateMac(_message(grantId, lifeTrackId, replyKey), secretKey: key)).bytes;
  }

  /// Patient side: made with the reply key pair, for one doctor's key.
  static Future<String> make({
    required SimpleKeyPair replyKeyPair,
    required List<int> doctorKey,
    required String grantId,
    required String lifeTrackId,
  }) async {
    final replyKey = (await replyKeyPair.extractPublicKey()).bytes;
    return base64Encode(await _mac(replyKeyPair, doctorKey, grantId, lifeTrackId, replyKey));
  }

  /// Doctor side: true only if [proof] was made by the holder of [replyKey].
  static Future<bool> check({
    required SimpleKeyPair doctorKeyPair,
    required List<int> replyKey,
    required String grantId,
    required String lifeTrackId,
    required String proof,
  }) async {
    final List<int> given;
    try {
      given = base64Decode(proof);
    } on FormatException {
      return false;
    }
    if (replyKey.length != 32) return false;
    final want = await _mac(doctorKeyPair, replyKey, grantId, lifeTrackId, replyKey);
    if (given.length != want.length) return false;
    var d = 0;
    for (var i = 0; i < want.length; i++) {
      d |= given[i] ^ want[i];
    }
    return d == 0;
  }
}
