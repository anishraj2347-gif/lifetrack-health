import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('a sealed share opens only with the addressed key, and not after expiry', () async {
    final doctor = await X25519().newKeyPair();
    final pub = (await doctor.extractPublicKey()).bytes;
    final at = DateTime.utc(2026, 9, 30, 12);
    final env = await ShareEnvelope.seal(
      bundle: {'hello': 'doctor'},
      recipientKey: pub,
      keyId: await RelayApi.keyId(pub),
      grantId: 'g1',
      expiresAt: at.add(const Duration(hours: 4)),
    );
    expect(await ShareEnvelope.open(env, doctor, at), {'hello': 'doctor'});
    expect(ShareEnvelope.open(env, await X25519().newKeyPair(), at), throwsA(anything));
    expect(ShareEnvelope.open(env, doctor, at.add(const Duration(hours: 5))), throwsA(isA<ShareExpired>()));
    expect(utf8.decode(env).contains('doctor"'), isFalse, reason: 'plaintext never appears');
  });

  test('a patient mailbox id reveals nothing and is reproducible from the secret', () async {
    final (secret, mailbox) = await RelayApi.newPatientMailbox();
    expect(mailbox, startsWith('p-'));
    expect(mailbox.contains(secret), isFalse);
    expect(await RelayApi.patientMailboxFor(secret), mailbox);
  });

  test('a doctor pickup signature verifies with the signing key and only for that mailbox, time and nonce', () async {
    final sign = await Ed25519().newKeyPair();
    final at = DateTime.utc(2026, 9, 30, 12);
    final h = await RelayApi.doctorPickupHeaders(certificateQr: 'x', signingKey: sign, mailbox: 'd-abc', at: at);
    final nonce = h[RelayApi.hNonce]!;
    final sig = Signature(base64Decode(h[RelayApi.hSig]!), publicKey: await sign.extractPublicKey());
    expect(await Ed25519().verify(RelayApi.pickupMessage('d-abc', at, nonce), signature: sig), isTrue);
    expect(await Ed25519().verify(RelayApi.pickupMessage('d-xyz', at, nonce), signature: sig), isFalse);
    expect(await Ed25519().verify(RelayApi.pickupMessage('d-abc', at, 'another'), signature: sig), isFalse);
  });

  test('every pickup carries a different nonce', () async {
    final sign = await Ed25519().newKeyPair();
    final at = DateTime.utc(2026, 9, 30, 12);
    final a = await RelayApi.doctorPickupHeaders(certificateQr: 'x', signingKey: sign, mailbox: 'd-abc', at: at);
    final b = await RelayApi.doctorPickupHeaders(certificateQr: 'x', signingKey: sign, mailbox: 'd-abc', at: at);
    expect(a[RelayApi.hNonce], isNot(b[RelayApi.hNonce]));
  });
}
