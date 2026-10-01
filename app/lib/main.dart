import 'package:flutter/widgets.dart';

import 'src/app/app_services.dart';
import 'src/app/storage_wiring.dart';
import 'src/crypto/device_key_store.dart';
import 'src/crypto/key_derivation.dart';
import 'src/reminders/local_notification_scheduler.dart';
import 'src/security/unlocker.dart';
import 'src/share/http_relay_client.dart';
import 'src/ui/lifetrack_app.dart';
import 'src/vault/backup_vault.dart';

/// Composition root. Wiring only — no domain decisions live here.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LifeTrackApp(
    boot: () async => AppServices.open(
      bytes: await openDeviceByteStore(),
      deviceKey: await SecureDeviceKeyStore().deviceKey(),
      // Backups live on the same LifeTrack server as the relay.
      remote: const String.fromEnvironment('LT_RELAY_URL').isEmpty
          ? InMemoryRemoteVaultStore()
          : HttpRemoteVaultStore(baseUrl: Uri.parse(const String.fromEnvironment('LT_RELAY_URL'))),
      backupEnabled: const String.fromEnvironment('LT_RELAY_URL').isNotEmpty,
      // Every profile verified through DigiLocker (user decision, 1 Oct 2026).
      identityRequired: const String.fromEnvironment('LT_IDENTITY') == 'required',
      demoTools: const bool.fromEnvironment('LT_DEMO_TOOLS'),
      reminderScheduler: LocalNotificationScheduler(),
      kdf: KdfParams.production,
      cloudFactory: defaultCloud,
      share: const ShareConfig(
        relayUrl: String.fromEnvironment('LT_RELAY_URL'),
        registryKey: String.fromEnvironment('LT_REGISTRY_KEY'),
      ),
    ),
    unlocker: DeviceUnlocker(),
  ));
}
