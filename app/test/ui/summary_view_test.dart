import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/widgets/summary_view.dart';

void main() {
  testWidgets('conditions show their year, family illnesses their onset, allergies their reaction', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SummaryView(bundle: const {
            'allergies': [{'substance': 'Penicillin', 'reaction': 'rash'}],
            'conditions': [{'name': 'Type 2 diabetes', 'since': 2019}],
            'familyIllnesses': {'items': [{'relation': 'father', 'condition': 'Heart attack', 'onset': 52}]},
          }),
        ),
      ),
    ));
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('since 2019'), findsOneWidget);
    expect(find.text('father: Heart attack'), findsOneWidget);
    expect(find.text('at 52'), findsOneWidget);
    expect(find.text('Allergy: Penicillin — rash'), findsOneWidget);
    expect(find.textContaining('t('), findsNothing);
  });
}
