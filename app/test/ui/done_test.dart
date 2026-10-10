import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';

void main() {
  testWidgets('celebrate shows the tick and the word, then removes itself with no timer left', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => celebrate(context, 'Record saved'), child: Text('Save')))),
    ));
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Record saved'), findsOneWidget);
    expect(find.byType(DoneMark), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Record saved'), findsNothing);
  });
}
