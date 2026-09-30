import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// The relay's HTTP contract. The relay only ever sees ciphertext, mailbox
/// ids, grant ids, expiry times and hashes of tokens.
///
/// Mailboxes:
/// - `d-<keyId>` — a doctor device, keyed by its encryption key. Picked up
///   only with a request signed by the certificate's signing key.
/// - `p-<hash>` — a patient's reply mailbox (prescriptions coming back).
///   The id is the SHA-256 of a secret only the patient's phone holds;
///   picked up by presenting the secret.
abstract final class RelayApi {
  static const version = 'v1';
  static const maxHold = Duration(hours: 48);
  static const signatureSkew = Duration(minutes: 5);

  static const hExpires = 'x-lt-expires';
  static const hWithdrawHash = 'x-lt-withdraw-hash';
  static const hWithdrawToken = 'x-lt-withdraw-token';
  static const hCert = 'x-lt-cert';
  static const hTime = 'x-lt-time';
  static const hSig = 'x-lt-sig';
  static const hMailboxSecret = 'x-lt-mailbox-secret';
  static const hAdmin = 'x-lt-admin';

  /// Proves the backup password (its login verifier) to update, open or
  /// delete a backup.
  static const hVerifier = 'x-lt-verifier';

  /// Proves ownership of a LifeTrack ID (the token its phone registered).
  static const hIdToken = 'x-lt-id-token';

  /// The secret that collects one identity verification result.
  static const hSessionSecret = 'x-lt-session-secret';

  static String mailboxPath(String mailbox) => '/$version/relay/$mailbox';
  static String itemPath(String mailbox, String grantId) => '/$version/relay/$mailbox/${Uri.encodeComponent(grantId)}';

  static Future<String> keyId(List<int> publicKey) async {
    final h = await Sha256().hash(publicKey);
    return h.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> doctorMailbox(List<int> encryptionKey) async => 'd-${await keyId(encryptionKey)}';

  /// A fresh reply mailbox for a patient: (secret to keep, mailbox id to share).
  static Future<(String secret, String mailbox)> newPatientMailbox([Random? rng]) async {
    final r = rng ?? Random.secure();
    final secret = base64Url.encode(List.generate(32, (_) => r.nextInt(256)));
    return (secret, await patientMailboxFor(secret));
  }

  static Future<String> patientMailboxFor(String secret) async => 'p-${await sha256Hex(secret)}';

  static Future<String> sha256Hex(String s) async =>
      (await Sha256().hash(utf8.encode(s))).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String newToken([Random? rng]) {
    final r = rng ?? Random.secure();
    return base64Url.encode(List.generate(24, (_) => r.nextInt(256)));
  }

  /// What a doctor signs to pick up its mailbox.
  static List<int> pickupMessage(String mailbox, DateTime at) =>
      utf8.encode('GET|${mailboxPath(mailbox)}|${at.toUtc().toIso8601String()}');

  static Future<Map<String, String>> doctorPickupHeaders({
    required String certificateQr,
    required SimpleKeyPair signingKey,
    required String mailbox,
    required DateTime at,
  }) async {
    final sig = await Ed25519().sign(pickupMessage(mailbox, at), keyPair: signingKey);
    return {hCert: certificateQr, hTime: at.toUtc().toIso8601String(), hSig: base64Encode(sig.bytes)};
  }
}
