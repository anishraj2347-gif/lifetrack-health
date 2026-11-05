import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ai/insight.dart';
import 'package:lifetrack/src/ai/plane_a/critical_check.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/ui/widgets/critical_prompt.dart';

import '../invariants/source.dart';

void main() {
  final at = DateTime(2026, 11, 6);
  HealthRecord report(LabResult r) => HealthRecord(id: 'r', patientId: 'p', kind: RecordKind.report, title: 'R', date: at, source: RecordSource.typedByPatient, results: [r]);

  Widget host(InsightRun run) => MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showCriticalPrompt(c, run), child: const Text('open')))),
        ),
      );

  testWidgets('an urgent value offers 108, and a tap outside does not close it', (t) async {
    await t.pumpWidget(host(CriticalCheck.record(patient: null, at: at, record: report(const LabResult(analyte: 'potassium', value: 6.5, unit: 'mmol/L')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Saved. Please read this now'), findsOneWidget);
    expect(find.textContaining('Potassium was 6.5 mmol/L'), findsOneWidget);
    expect(find.textContaining('call 108'), findsOneWidget);
    expect(find.text('Call 108'), findsOneWidget);
    await t.tapAt(const Offset(2, 2));
    await t.pumpAndSettle();
    expect(find.text('Saved. Please read this now'), findsOneWidget);
    await t.tap(find.text('I have read this'));
    await t.pumpAndSettle();
    expect(find.text('Saved. Please read this now'), findsNothing);
  });

  testWidgets('a value it cannot judge is said to be unchecked, never fine', (t) async {
    await t.pumpWidget(host(CriticalCheck.record(patient: null, at: at, record: report(const LabResult(analyte: 'potassium', value: 65, unit: '')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Saved, but not checked'), findsOneWidget);
    expect(find.textContaining('says nothing about whether the value is fine'), findsOneWidget);
    expect(find.text('Call 108'), findsNothing);
  });

  test('every screen that saves a lab value or a reading shows the check', () {
    final saves = RegExp(r'\.(addRecord|updateRecord|addScannedAll|addScanned|addVital)\(');
    for (final f in dartFiles('lib').cast<File>()) {
      final rel = f.path.replaceAll(r'\', '/');
      if (!rel.startsWith('lib/src/ui/')) continue;
      final code = codeOf(f);
      if (saves.hasMatch(code)) expect(code.contains('showCriticalPrompt('), isTrue, reason: rel);
    }
  });
}
