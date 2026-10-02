import 'dart:typed_data';

import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// The encrypted mailbox between a patient's phone and a doctor's device.
///
/// It carries ciphertext it cannot open and deletes it on pickup or at expiry
/// (CLAUDE.md #1b). Mailbox ids follow `RelayApi`: `d-…` for a doctor
/// device, `p-…` for a patient's reply mailbox.
abstract interface class RelayClient {
  Future<void> deposit({required String mailbox, required String grantId, required Uint8List envelope, required DateTime expiresAt});

  /// Revocation: removes an undelivered share. A share already picked up is
  /// out of reach — the doctor app is asked to discard it, which is
  /// cooperative, and the UI says so.
  Future<void> withdraw({required String mailbox, required String grantId});

  /// The patient collects their reply mailbox (prescriptions coming back).
  Future<List<Uint8List>> collect({required String mailbox, required String secret});
}

/// Whether the registry still approves a doctor with exactly the keys in a
/// certificate. Certificates last 30 days; this catches a revocation inside
/// that time whenever the phone is online.
abstract interface class DoctorStatus {
  /// True: still approved with these keys. False: revoked, re-enrolled with
  /// other keys, or unknown to the registry. Null: could not ask (offline) —
  /// the certificate's own validity then decides.
  Future<bool?> stillApproved(DoctorCertificate cert);
}

/// Never asks; for tests and builds with no registry to ask.
class UnknownDoctorStatus implements DoctorStatus {
  const UnknownDoctorStatus();
  @override
  Future<bool?> stillApproved(DoctorCertificate cert) async => null;
}

/// A message in a reply mailbox refused for a reason the access log names.
abstract interface class MessageRefused implements Exception {
  String get reason;
}

/// For tests and for the doctor-side simulation.
class InMemoryRelay implements RelayClient {
  final Map<String, Map<String, (Uint8List, DateTime)>> _boxes = {};

  @override
  Future<void> deposit({required String mailbox, required String grantId, required Uint8List envelope, required DateTime expiresAt}) async =>
      (_boxes[mailbox] ??= {})[grantId] = (envelope, expiresAt);

  @override
  Future<void> withdraw({required String mailbox, required String grantId}) async => _boxes[mailbox]?.remove(grantId);

  @override
  Future<List<Uint8List>> collect({required String mailbox, required String secret}) async =>
      [for (final (env, _) in (_boxes.remove(mailbox) ?? {}).values) env];

  /// Doctor pickup: returns and deletes every unexpired share.
  List<Uint8List> pickUp(String mailbox, DateTime at) {
    final box = _boxes.remove(mailbox) ?? {};
    return [for (final (env, exp) in box.values) if (at.isBefore(exp)) env];
  }

  int pending(String mailbox) => _boxes[mailbox]?.length ?? 0;
}
