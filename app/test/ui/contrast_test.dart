import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/screens/abha_screen.dart';
import 'package:lifetrack/src/ui/screens/add_family_screen.dart';
import 'package:lifetrack/src/ui/screens/add_record_screen.dart';
import 'package:lifetrack/src/ui/screens/backup_screens.dart';
import 'package:lifetrack/src/ui/screens/custom_reminder_screen.dart';
import 'package:lifetrack/src/ui/screens/data_rights_screen.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/ui/screens/emergency_screen.dart';
import 'package:lifetrack/src/ui/screens/show_on_phone_screen.dart';
import 'package:lifetrack/src/ui/screens/me_screen.dart';
import 'package:lifetrack/src/ui/screens/reminders_screen.dart';
import 'package:lifetrack/src/ui/screens/tests_you_have_screen.dart';
import 'package:lifetrack/src/ui/screens/vaccinations_screen.dart';
import 'package:lifetrack/src/ui/screens/vitals_screen.dart';
import 'package:lifetrack/src/ui/screens/family_overview_screen.dart';
import 'package:lifetrack/src/ui/screens/record_screen.dart';
import 'package:lifetrack/src/ui/screens/test_trend_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

import 'contrast_check.dart';

/// Text must be readable against what is behind it — in particular, nothing
/// dark on the black cards. Flutter's own contrast guideline (WCAG AA: 4.5:1,
/// 3:1 for large text), checked on the rendered pixels of each main screen.
void main() {
  final now = DateTime(2026, 10, 1, 10);

  Future<AppServices> open() async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 5)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => now,
      demoTools: true,
    );
    await s.createProfile(
      name: 'Anjali Sharma',
      dob: DateTime(1984),
      sex: Sex.female,
    );
    await s.addSampleRecords();
    await s.addChild(
      name: 'Aarav Sharma',
      dob: DateTime(2021),
      sex: Sex.male,
      relation: 'son',
    );
    await s.switchTo(s.selfPatientId!);
    return s;
  }

  Future<void> check(WidgetTester tester, String where) async {
    await tester.pumpAndSettle();
    expect(lowContrastTexts(tester, page: LT.ground), isEmpty, reason: where);
    await expectLater(
      tester,
      meetsGuideline(textContrastGuideline),
      reason: where,
    );
  }

  for (final mode in ['light', 'dark']) {
    testWidgets(
      'main screens, $mode: every text is readable on its background',
      (tester) async {
        final handle = tester.ensureSemantics();
        addTearDown(() {
          appearance.value = ThemeMode.system;
          LT.dark = false;
        });
        late AppServices s;
        await tester.runAsync(() async {
          s = await open();
          await s.setThemeChoice(mode);
        });
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(LifeTrackApp(boot: () async => s));
        await tester.pumpAndSettle();
        expect(LT.dark, mode == 'dark');

        await check(tester, 'Reminders');
        for (final tab in ['Records', 'Insights', 'Share', 'Me']) {
          await tester.tap(find.bySemanticsLabel(tab));
          await check(tester, tab);
        }

        await tester.scrollUntilVisible(
          find.text('Family overview'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        // Centre it: lists scroll under the glass tab bar.
        await tester.runAsync(() => Scrollable.ensureVisible(tester.element(find.text('Family overview')), alignment: 0.5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Family overview'));
        await check(tester, 'Family overview');
        Navigator.of(tester.element(find.byType(FamilyOverviewScreen))).pop();
        await tester.pumpAndSettle();

        final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
        final finished = s.records().firstWhere(
          (r) => r.title == 'Glycomet 500 SR',
        );
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => RecordScreen(recordId: finished.id),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Course finished'),
          findsOneWidget,
          reason: 'the finished course is on screen',
        );
        await check(tester, 'A finished course (badge on the black card)');
        nav.pop();
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const TestTrendScreen(analyte: 'hba1c', unit: '%'),
          ),
        );
        await check(tester, 'Results over time');
        nav.pop();
        for (final (name, screen) in <(String, Widget)>[
          ('Emergency ID', const EmergencyScreen()),
          (
            'Emergency ID editor',
            Scaffold(
              body: EmergencyEditor(patientId: s.selfPatientId!, initial: EmergencyCard(), onSaved: () {}),
            ),
          ),
          ('Show on my phone', const ShowOnPhoneScreen()),
          ('Reminder settings', const RemindersScreen()),
          ('New reminder', const CustomReminderScreen()),
          ('Tests you already have', const TestsYouHaveScreen()),
          ('BP & sugar diary', const VitalsScreen()),
          ('Backup', const BackupScreen()),
          ('Your data and your rights', const DataRightsScreen()),
          ('Access log', const AuditScreen()),
          ('ABHA', const AbhaScreen()),
          ('Add record', const AddRecordScreen()),
          ('Add family', const AddFamilyScreen()),
        ]) {
          nav.push(MaterialPageRoute<void>(builder: (_) => screen));
          await check(tester, name);
          nav.pop();
          await tester.pumpAndSettle();
        }
        // A child's profile: vaccinations.
        await s.switchTo(s.familyOnPhone().last.id);
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const VaccinationsScreen()),
        );
        await check(tester, 'Vaccinations');
        handle.dispose();
      },
    );
  }
}
