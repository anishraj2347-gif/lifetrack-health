import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/widgets/trend_card.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final now = DateTime(2026, 10, 1, 10);

  testWidgets('swiping a medicine sideways ticks it taken, and swiping again undoes it', (tester) async {
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 7)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.addRecord(HealthRecord(
        id: 'rx1',
        patientId: s.selfPatientId!,
        kind: RecordKind.prescription,
        title: 'Telmisartan 40 mg',
        date: now,
        source: RecordSource.typedByPatient,
        dose: const Dose(morning: 1, afternoon: 0, night: 0),
      ));
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LifeTrackApp(boot: () async => s));
    await tester.pumpAndSettle();

    final slot = s.todaysDoses().single.$1;
    expect(s.takenToday(slot, 'rx1'), isFalse);
    await tester.drag(find.byType(Dismissible).first, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(s.takenToday(slot, 'rx1'), isTrue);
    expect(find.byType(Dismissible), findsOneWidget, reason: 'the row springs back, it is not removed');
    await tester.drag(find.byType(Dismissible).first, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(s.takenToday(slot, 'rx1'), isFalse);
  });

  testWidgets('touching a trend column shows that result and its date', (tester) async {
    HealthRecord lab(String id, DateTime d, double v) => HealthRecord(
          id: id,
          patientId: 'p',
          kind: RecordKind.report,
          title: 'Lipid panel',
          date: d,
          source: RecordSource.typedByPatient,
          results: [LabResult(analyte: 'cholesterol_total', value: v, unit: 'mg/dL')],
        );
    final records = [lab('a', DateTime(2025, 9, 1), 205), lab('b', DateTime(2026, 3, 1), 201), lab('c', DateTime(2026, 9, 1), 198)];
    final series = TrendCard.all(records).single;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: TrendCard(series: series)))));
    await tester.pumpAndSettle();
    expect(find.text('198'), findsOneWidget);
    expect(find.textContaining('Latest'), findsOneWidget);
    final chart = tester.getRect(find.byType(GestureDetector).last);
    await tester.tapAt(Offset(chart.left + chart.width / 6, chart.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('205'), findsOneWidget);
    expect(find.text('1 Sep 2025'), findsOneWidget);
    expect(find.textContaining('Latest'), findsNothing);
  });
}
