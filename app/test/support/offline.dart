import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// A relay that can be switched off, as the laptop server is between demos.
class SwitchableRelay implements RelayClient {
  SwitchableRelay([InMemoryRelay? inner]) : inner = inner ?? InMemoryRelay();
  final InMemoryRelay inner;
  bool down = false;

  /// Runs at the start of every call, up or down: lets a test check what was
  /// already on the record when the phone reached for the network.
  void Function()? onCall;
  int calls = 0;

  void _touch() {
    calls++;
    onCall?.call();
    if (down) throw const SocketLikeFailure();
  }

  @override
  Future<void> deposit({required String mailbox, required String grantId, required Uint8List envelope, required DateTime expiresAt}) async {
    _touch();
    await inner.deposit(mailbox: mailbox, grantId: grantId, envelope: envelope, expiresAt: expiresAt);
  }

  @override
  Future<void> withdraw({required String mailbox, required String grantId}) async {
    _touch();
    await inner.withdraw(mailbox: mailbox, grantId: grantId);
  }

  @override
  Future<List<Uint8List>> collect({required String mailbox, required String secret}) async {
    _touch();
    return inner.collect(mailbox: mailbox, secret: secret);
  }
}

class SocketLikeFailure implements Exception {
  const SocketLikeFailure();
  @override
  String toString() => 'SocketException: Connection refused';
}

/// A registered doctor's device, as the doctor app would hold it.
class TestDoctor {
  TestDoctor(this.enc, this.sign, this.qr);
  final SimpleKeyPair enc;
  final SimpleKeyPair sign;
  final String qr;

  DoctorCertificate get cert => DoctorCertificate.decode(qr);

  static Future<TestDoctor> make(SimpleKeyPair registry, {String id = 'DMC-12345'}) async {
    final enc = await X25519().newKeyPair();
    final sign = await Ed25519().newKeyPair();
    final unsigned = DoctorCertificate(
      registryId: id,
      name: 'Dr. R. Mehta',
      speciality: 'Cardiology',
      council: 'Delhi Medical Council',
      registrationNo: id,
      encryptionKey: (await enc.extractPublicKey()).bytes,
      signingKey: (await sign.extractPublicKey()).bytes,
      issuedAt: DateTime(2026),
      expiresAt: DateTime(2027),
      signature: const [],
    );
    final sig = await Ed25519().sign(unsigned.signedBytes, keyPair: registry);
    final cert = DoctorCertificate(
      registryId: unsigned.registryId,
      name: unsigned.name,
      speciality: unsigned.speciality,
      council: unsigned.council,
      registrationNo: unsigned.registrationNo,
      encryptionKey: unsigned.encryptionKey,
      signingKey: unsigned.signingKey,
      issuedAt: unsigned.issuedAt,
      expiresAt: unsigned.expiresAt,
      signature: sig.bytes,
    );
    return TestDoctor(enc, sign, cert.encode());
  }

  /// Everything waiting for this device, opened.
  Future<List<Map<String, Object?>>> pickUp(InMemoryRelay relay, DateTime at) async {
    final mailbox = await RelayApi.doctorMailbox(cert.encryptionKey);
    return [for (final e in relay.pickUp(mailbox, at)) await ShareEnvelope.open(e, enc, at)];
  }
}

/// One phone: [bytes] survive a "restart" (a second [open] over them).
class TestPhone {
  TestPhone({required this.relay, required this.registry, this.now, RemoteVaultStore? remote, IdDirectory? ids, this.retryAfter})
      : remote = remote ?? InMemoryRemoteVaultStore(),
        ids = ids ?? InMemoryIdDirectory();

  final SwitchableRelay relay;
  final SimpleKeyPair registry;
  final RemoteVaultStore remote;
  final IdDirectory ids;
  final Duration? retryAfter;
  final DateTime Function()? now;
  final ByteStore bytes = InMemoryByteStore();

  Future<AppServices> open() async => AppServices.open(
        bytes: bytes,
        deviceKey: SecretKey(List.filled(32, 9)),
        remote: remote,
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: now,
        share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
        relayOverride: (_) => relay,
        idDirectoryOverride: () => ids,
        retryAfter: retryAfter,
      );
}
