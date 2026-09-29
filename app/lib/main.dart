import 'package:flutter/widgets.dart';

import 'src/app/app_services.dart';
import 'src/app/storage_wiring.dart';
import 'src/crypto/device_key_store.dart';
import 'src/crypto/key_derivation.dart';
import 'src/ui/lifetrack_app.dart';
import 'src/vault/backup_vault.dart';

/// Composition root. Wiring only — no domain decisions live here.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LifeTrackApp(
    boot: () async => AppServices.open(
      bytes: await openDeviceByteStore(),
      deviceKey: await SecureDeviceKeyStore().deviceKey(),
      // No backup server exists yet; the vault logic is built and tested
      // against this stand-in and is not reachable from the UI.
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.production,
      cloudFactory: defaultCloud,
    ),
  ));
}
