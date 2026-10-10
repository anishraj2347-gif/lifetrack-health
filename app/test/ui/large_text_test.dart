import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/screens/add_family_screen.dart';
import 'package:lifetrack/src/ui/screens/add_record_screen.dart';
import 'package:lifetrack/src/ui/screens/backup_screens.dart';
import 'package:lifetrack/src/ui/screens/data_rights_screen.dart';
import 'package:lifetrack/src/ui/screens/emergency_screen.dart';
import 'package:lifetrack/src/ui/screens/family_overview_screen.dart';
import 'package:lifetrack/src/ui/screens/reminders_screen.dart';
import 'package:lifetrack/src/ui/screens/show_on_phone_screen.dart';
import 'package:lifetrack/src/ui/screens/vitals_screen.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Many older users run their phone at large or huge text. At 2× nothing on
/// the five main tabs may overflow (Flutter reports overflow as an error).
void main() {
  final now = DateTime(2026, 10, 1, 10);

  testWidgets('the main tabs lay out at twice the text size', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 8)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
        demoTools: true,
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.addSampleRecords();
      await s.addChild(name: 'Aarav Sharma', dob: DateTime(2021), sex: Sex.male, relation: 'son');
      await s.switchTo(s.selfPatientId!);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Reminders');
    for (final tab in ['Records', 'Insights', 'Share', 'Me']) {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
    }
    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    for (final screen in const <Widget>[
      EmergencyScreen(),
      AddRecordScreen(),
      RemindersScreen(),
      BackupScreen(),
      DataRightsScreen(),
      AddFamilyScreen(),
      FamilyOverviewScreen(),
      ShowOnPhoneScreen(),
      VitalsScreen(),
    ]) {
      nav.push(MaterialPageRoute<void>(builder: (_) => screen));
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
    }
  });
}
