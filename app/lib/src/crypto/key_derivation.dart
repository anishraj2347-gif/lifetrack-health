import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

/// Argon2id cost parameters.
class KdfParams {
  const KdfParams._(this.memoryKiB, this.iterations, this.parallelism);

  /// OWASP 2024 minimum for Argon2id: 19 MiB, 2 passes, 1 lane.
  static const production = KdfParams._(19456, 2, 1);

  /// Fast parameters for tests. **Throws in release** — `throw`, not
  /// `assert`, because asserts are stripped from release builds and a
  /// stripped guard is no guard (CLAUDE.md #2a).
  static KdfParams weakForTests() {
    if (kReleaseMode) {
      throw StateError('Weak KDF parameters are refused in a release build.');
    }
    return const KdfParams._(64, 1, 1);
  }

  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

/// The two secrets one passphrase yields.
///
/// [vaultKey] opens the backup and never leaves the phone. [loginVerifier]
/// goes to the server to fetch the locked backup. They come off one Argon2id
/// root through distinct HKDF labels, so the verifier cannot open anything.
///
/// Residual (Mechanisms fig. 2): the server holding the verifier, the salt
/// and the ciphertext together can still guess the passphrase offline. Until
/// a PAKE or a system-generated passphrase closes that, no UI string may
/// claim LifeTrack is unable to open the backup (CLAUDE.md #2).
class DerivedKeys {
  DerivedKeys(this.vaultKey, this.loginVerifier);
  final SecretKey vaultKey;
  final List<int> loginVerifier;
}

abstract final class VaultKeyDerivation {
  static const _vaultLabel = 'lifetrack/v1/vault-key';
  static const _verifierLabel = 'lifetrack/v1/login-verifier';

  /// Runs Argon2id on a background isolate: at production cost it takes long
  /// enough to drop frames if run on the UI thread.
  static Future<DerivedKeys> derive(String passphrase, List<int> salt, KdfParams params) async {
    final root = await Isolate.run(() => _argon(passphrase, salt, params));
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final rootKey = SecretKey(root);
    final vault = await hkdf.deriveKey(secretKey: rootKey, nonce: salt, info: utf8.encode(_vaultLabel));
    final verifier = await hkdf.deriveKey(secretKey: rootKey, nonce: salt, info: utf8.encode(_verifierLabel));
    return DerivedKeys(SecretKey(await vault.extractBytes()), await verifier.extractBytes());
  }

  static Future<List<int>> _argon(String passphrase, List<int> salt, KdfParams p) async {
    final algo = Argon2id(
      memory: p.memoryKiB,
      iterations: p.iterations,
      parallelism: p.parallelism,
      hashLength: 32,
    );
    final key = await algo.deriveKeyFromPassword(password: passphrase, nonce: salt);
    return key.extractBytes();
  }
}
