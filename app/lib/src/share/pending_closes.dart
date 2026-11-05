/// What became of a patient ending access.
enum EndAccessResult {
  /// The relay took the withdrawal and, if the share may have been picked up,
  /// the close message for the doctor's device.
  doctorToldNow,

  /// Ended on this phone, but the relay could not be reached. The withdrawal
  /// and close message wait in the queue and go when it can be reached.
  waitingForServer,
}

/// A doctor's device still to be told that access ended. Everything needed
/// is held here, so the message can still go after a restart, or after the
/// profile it belongs to has been erased. Sealed under the device key.
class PendingClose {
  const PendingClose({
    required this.grantId,
    required this.patientId,
    required this.doctorActorId,
    required this.keyId,
    required this.expiresAt,
    this.doctorKey,
    this.closeSecret,
    this.replaced = false,
  });

  final String grantId;
  final String patientId;
  final String doctorActorId;
  final String keyId;
  final DateTime expiresAt;

  /// The doctor device's key, base64. Null when this phone never held one:
  /// only the withdrawal is then outstanding.
  final String? doctorKey;

  /// Proves the close came from this phone; see the share's `closeSecret`.
  final String? closeSecret;

  /// A new share took its place, so the doctor app announces nothing.
  final bool replaced;

  String get mailbox => 'd-$keyId';

  Map<String, Object?> toJson() => {
        'grant': grantId,
        'patient': patientId,
        'actor': doctorActorId,
        'keyId': keyId,
        'exp': expiresAt.toUtc().toIso8601String(),
        'key': doctorKey,
        'secret': closeSecret,
        'replaced': replaced,
      };

  static PendingClose fromJson(Map<String, Object?> j) => PendingClose(
        grantId: j['grant']! as String,
        patientId: j['patient']! as String,
        doctorActorId: j['actor']! as String,
        keyId: j['keyId']! as String,
        expiresAt: DateTime.parse(j['exp']! as String),
        doctorKey: j['key'] as String?,
        closeSecret: j['secret'] as String?,
        replaced: (j['replaced'] as bool?) ?? false,
      );
}

/// Durable on the phone (`_SealedCloses`); a list in tests.
abstract interface class PendingCloseStore {
  Future<List<PendingClose>> load();
  Future<void> save(List<PendingClose> all);
}

class InMemoryPendingCloses implements PendingCloseStore {
  List<PendingClose> saved = const [];
  @override
  Future<List<PendingClose>> load() async => [...saved];
  @override
  Future<void> save(List<PendingClose> all) async => saved = [...all];
}
