import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/screens/abha_screen.dart';
import 'package:lifetrack/src/ui/screens/add_family_screen.dart';
import 'package:lifetrack/src/ui/screens/add_record_screen.dart';
import 'package:lifetrack/src/ui/screens/backup_screens.dart';
import 'package:lifetrack/src/ui/screens/custom_reminder_screen.dart';
import 'package:lifetrack/src/ui/screens/data_rights_screen.dart';
import 'package:lifetrack/src/ui/screens/doctor_share_screen.dart';
import 'package:lifetrack/src/ui/screens/emergency_screen.dart';
import 'package:lifetrack/src/ui/screens/family_link_screens.dart' show JoinFamilyScreen;
import 'package:lifetrack/src/ui/screens/family_overview_screen.dart';
import 'package:lifetrack/src/ui/screens/me_screen.dart';
import 'package:lifetrack/src/ui/screens/record_screen.dart';
import 'package:lifetrack/src/ui/screens/reminders_screen.dart';
import 'package:lifetrack/src/ui/screens/show_on_phone_screen.dart';
import 'package:lifetrack/src/ui/screens/tests_you_have_screen.dart';
import 'package:lifetrack/src/ui/screens/vaccinations_screen.dart';
import 'package:lifetrack/src/ui/screens/vitals_screen.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// Android's "Display size" makes the screen narrower in layout terms and
/// "Font size" makes text bigger. Every screen must lay out — no row or label
/// running past its box — from a small phone at large display size (320 wide)
/// to a usual one (411), at normal, 1.3× and 2× text. Flutter reports any
/// overflow as an error; this collects them all and names screen and size.
void main() {
  final now = DateTime(2026, 10, 1, 10);
  const widths = [320.0, 360.0, 411.0];
  const scales = [1.0, 1.3, 2.0];

  for (final width in widths) {
    for (final scale in scales) {
      testWidgets('every screen fits at ${width.toInt()} wide and ${scale}x text', (tester) async {
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
          await s.addDemoFamily();
          await s.switchTo(s.selfPatientId!);
        });
        const dpr = 3.0;
        tester.view.physicalSize = Size(width * dpr, width * dpr * 2.2);
        tester.view.devicePixelRatio = dpr;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final problems = <String>[];
        var where = 'start';
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final first = details.exceptionAsString().split('\n').first;
          final at = RegExp(r'lib/src/[\w/]+\.dart:\d+').firstMatch(details.toString())?.group(0) ?? '';
          problems.add('$where: $first $at');
        };
        try {
          await tester.pumpWidget(LifeTrackApp(boot: () async => s));
          await tester.pumpAndSettle();
          where = 'Reminders';
          await _scrollThrough(tester);
          for (final tab in ['Records', 'Insights', 'Share', 'Me']) {
            where = tab;
            await tester.tap(find.bySemanticsLabel(tab));
            await tester.pumpAndSettle();
            await _scrollThrough(tester);
          }
          // A shrunk label raises no error, so check by hand that each tab's
          // name sits inside its pill (inset 3 from the tab's edges).
          for (final tab in ['Reminders', 'Records', 'Insights', 'Share', 'Me']) {
            final slot = tester.getRect(find.bySemanticsLabel(tab));
            final label = tester.getRect(find.descendant(of: find.bySemanticsLabel(tab), matching: find.text(tab)));
            if (label.left < slot.left + 3 || label.right > slot.right - 3) problems.add('tab bar: "$tab" runs past its pill');
          }

          final records = s.records();
          final report = records.firstWhere((r) => r.kind == RecordKind.report && r.results.isNotEmpty);
          final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
          final screens = <String, Widget>{
            'Emergency ID': const EmergencyScreen(),
            'Add record': const AddRecordScreen(),
            'Reminders settings': const RemindersScreen(),
            'Create a reminder': const CustomReminderScreen(),
            'Backup': const BackupScreen(),
            'Restore': RestoreScreen(onRestored: () {}),
            'Data rights': const DataRightsScreen(),
            'Access log': const AuditScreen(),
            'Add family member': const AddFamilyScreen(),
            'Family overview': const FamilyOverviewScreen(),
            'Join a family': const JoinFamilyScreen(),
            'Show on phone': const ShowOnPhoneScreen(),
            'Vitals': const VitalsScreen(),
            'Vaccinations': const VaccinationsScreen(),
            'Tests you have': const TestsYouHaveScreen(),
            'ABHA': const AbhaScreen(),
            'Share with a doctor': const DoctorShareScreen(),
            'Record': RecordScreen(recordId: report.id),
            for (final r in records.where((r) => r.kind == RecordKind.prescription).take(1)) 'Prescription': RecordScreen(recordId: r.id),
          };
          for (final e in screens.entries) {
            where = e.key;
            nav.push(MaterialPageRoute<void>(builder: (_) => e.value));
            await tester.pumpAndSettle();
            await _scrollThrough(tester);
            nav.pop();
            await tester.pumpAndSettle();
          }
        } finally {
          FlutterError.onError = previous;
        }
        for (final p in problems.toSet()) {
          // ignore: avoid_print
          print('OVERFLOW ${width.toInt()}w ${scale}x — $p');
        }
        expect(problems.toSet().toList(), isEmpty);
      });
    }
  }
}

/// Fling down every scrollable on screen so lazily built rows lay out too.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(scrollables.at(i));
    if (state.axisDirection != AxisDirection.down) continue;
    final position = state.position;
    while (position.pixels < position.maxScrollExtent) {
      position.jumpTo((position.pixels + 600).clamp(0, position.maxScrollExtent));
      await tester.pump();
    }
    position.jumpTo(0);
    await tester.pump();
  }
}
