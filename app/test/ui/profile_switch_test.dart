import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  testWidgets('switch back to You survives Share → Check for prescriptions and updates → Me', (tester) async {
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
      final c = await s.addChild(name: 'Baby of Anjali Sharma', dob: DateTime(2026, 8, 20), sex: Sex.male, relation: 'son');
      await s.switchTo(c.id);
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    expect(s.currentPatient!.name, 'Baby of Anjali Sharma');
    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(s.currentPatient!.name, 'Anjali Sharma', reason: 'after tapping You');
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Check for prescriptions and updates'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(s.currentPatient!.name, 'Anjali Sharma', reason: 'after check for updates');
    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    expect(find.text('Anjali Sharma'), findsWidgets);
  });
}
