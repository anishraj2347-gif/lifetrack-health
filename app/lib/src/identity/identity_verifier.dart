import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// Why a verification did not give a usable identity. [message] is written
/// for the person holding the phone.
class VerificationFailed implements Exception {
  const VerificationFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One DigiLocker check, as the LifeTrack service runs it: start a session,
/// send the person to [authorizeUrl], then collect the signed result.
abstract interface class IdentityVerifier {
  /// `self` for someone with their own Aadhaar; `newborn` with the verified
  /// parent's [parent] attestation for a baby with only a birth certificate.
  Future<VerifySession> start({required String purpose, IdentityAttestation? parent});

  /// `{status: pending|done|error|expired, attestation?, error?}`.
  Future<Map<String, Object?>> poll(VerifySession s);
}

class VerifySession {
  const VerifySession({required this.id, required this.secret, required this.authorizeUrl});
  final String id;
  final String secret;
  final Uri authorizeUrl;
}

/// Opens DigiLocker in the browser, waits for the person to finish, and
/// checks the result was signed by the LifeTrack service this app trusts —
/// a result nobody signed, or anyone else signed, is refused.
Future<IdentityAttestation> runVerification({
  required IdentityVerifier verifier,
  required RegistryTrust trust,
  required String purpose,
  IdentityAttestation? parent,
  required Future<void> Function(Uri url) openUrl,
  Duration every = const Duration(seconds: 2),
  Duration giveUpAfter = const Duration(minutes: 10),
}) async {
  final session = await verifier.start(purpose: purpose, parent: parent);
  await openUrl(session.authorizeUrl);
  final deadline = DateTime.now().add(giveUpAfter);
  while (DateTime.now().isBefore(deadline)) {
    final r = await verifier.poll(session);
    switch (r['status']) {
      case 'done':
        final a = IdentityAttestation.fromJson((r['attestation']! as Map).cast());
        if (!await a.verifies(trust)) throw const VerificationFailed('The result did not come from LifeTrack. Nothing was saved.');
        return a;
      case 'error':
        throw VerificationFailed('${r['error']}');
      case 'expired':
        throw const VerificationFailed('The check took too long. Start again.');
    }
    await Future<void>.delayed(every);
  }
  throw const VerificationFailed('The check took too long. Start again.');
}

/// Duplicate person: this identity already has a LifeTrack ID.
class PersonExists implements Exception {
  const PersonExists();
  String get message => 'This person already has a LifeTrack profile. Restore it from backup on this phone instead of making a new one.';
}
