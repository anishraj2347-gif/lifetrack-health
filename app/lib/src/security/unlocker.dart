import 'package:local_auth/local_auth.dart';

/// Asks the phone's own screen lock — fingerprint, face, PIN or pattern —
/// to confirm the person holding it. LifeTrack never sees or stores any of
/// them.
abstract class Unlocker {
  /// False when the phone has no screen lock set, so there is nothing to ask.
  Future<bool> available();
  Future<bool> unlock(String reason);
}

class DeviceUnlocker implements Unlocker {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on Object {
      // Cancelled, locked out, or no credential enrolled: stay locked.
      return false;
    }
  }
}
