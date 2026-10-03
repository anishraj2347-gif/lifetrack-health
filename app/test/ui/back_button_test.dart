import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Android back, as in other apps: another tab → the first tab; on the
/// first tab, a second press leaves.
void main() {
  testWidgets('back returns to the first tab, then asks before leaving', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      final registry = await Ed25519().newKeyPair();
      s = await AppServices.open(
        bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 9)), remote: InMemoryRemoteVaultStore(), kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud, clock: () => DateTime(2026, 10, 1, 9),
        share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
        relayOverride: (_) => InMemoryRelay(), idDirectoryOverride: () => InMemoryIdDirectory(),
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    });
    final exits = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits.add(call);
      return null;
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    // Only the selected tab shows its name in the bar.
    expect(find.text('Me'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, isEmpty, reason: 'back from Me goes to Reminders, not out of the app');
    expect(find.text('Me'), findsNothing);
    expect(find.text('Reminders'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, hasLength(1), reason: 'the second press leaves');
  });
}
