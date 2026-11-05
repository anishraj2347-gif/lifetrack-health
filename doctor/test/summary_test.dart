import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/summary.dart';

void main() {
  Future<void> show(WidgetTester t, Map<String, Object?> bundle) =>
      t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SummaryPanel(bundle: bundle)))));

  testWidgets('an empty allergy list says "not recorded", never nothing', (t) async {
    await show(t, {'allergies': <Object?>[]});
    expect(find.text('Allergies: not recorded'), findsOneWidget);
    await show(t, const {});
    expect(find.text('Allergies: not recorded'), findsOneWidget, reason: 'a bundle from an older phone');
  });

  testWidgets('"no known allergies" is the patient\'s statement', (t) async {
    await show(t, {'allergies': <Object?>[], 'noKnownAllergies': true});
    expect(find.text('No known allergies, as stated by the patient'), findsOneWidget);
    expect(find.text('Allergies: not recorded'), findsNothing);
  });

  testWidgets('withheld allergies are not called unrecorded', (t) async {
    await show(t, {'allergies': <Object?>[], 'withheld': ['allergies']});
    expect(find.text('Allergies: not shared'), findsOneWidget);
    expect(find.text('Allergies: not recorded'), findsNothing);
  });

  testWidgets('allergies on the list are shown, and the empty line is not', (t) async {
    await show(t, {
      'allergies': [
        {'substance': 'Penicillin', 'reaction': 'rash'},
      ],
    });
    expect(find.text('Allergy: Penicillin — rash'), findsOneWidget);
    expect(find.text('Allergies: not recorded'), findsNothing);
  });

  testWidgets('a lab limit keeps its sign', (t) async {
    await show(t, {
      'latestTests': [
        {'analyte': 'glucose', 'value': 600, 'comparator': '>', 'unit': 'mg/dL', 'ageDays': 1, 'source': 'photoOfReport', 'recordId': 'r1', 'sampledOn': '2026-11-05T09:00:00.000', 'lab': 'City Lab'},
      ],
    });
    expect(find.text('Glucose, type not stated  >600 mg/dL'), findsOneWidget);
  });

  testWidgets('a dose saved in words is shown in Medicines', (t) async {
    await show(t, {
      'medicines': {
        'active': [
          {'title': 'Methotrexate 15 mg', 'dose': null, 'instructions': '15 mg once a week on Sunday'},
        ],
      },
    });
    expect(find.text('Methotrexate 15 mg · 15 mg once a week on Sunday'), findsOneWidget);
  });
}
