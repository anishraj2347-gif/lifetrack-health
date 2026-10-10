import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// The lime pill and the tab's name must line up after any number of
/// switches. (1.35.0's touch glow shifted a tab's content left after its
/// first tap, so the pill looked off-centre from the second switch on.)
void main() {
  testWidgets('after repeated switches each tab name stays centred under the lime pill', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 9)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => DateTime(2026, 10, 1, 10),
        demoTools: true,
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    // Small text, so each tab's content is narrower than its slot, as with
    // the real font on a phone; the placeholder test font fills the slot and
    // would hide a sideways shift.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    final pill = find.byWidgetPredicate((w) => w is FractionallySizedBox && w.widthFactor == 1 / 5);
    for (final n in ['Records', 'Insights', 'Share', 'Me', 'Reminders', 'Share', 'Records', 'Me', 'Insights', 'Records']) {
      await tester.tap(find.bySemanticsLabel(n));
      await tester.pumpAndSettle();
      final p = tester.getRect(pill.first).center.dx;
      // The icon, not the name: test text uses a placeholder font where names
      // overflow their slot and so always look centred.
      final icon = tester.getRect(find.descendant(of: find.bySemanticsLabel(n), matching: find.byType(Icon)).first).center.dx;
      expect((icon - p).abs(), lessThan(1.5), reason: '$n: icon at $icon, pill at $p');
    }
  });
}
