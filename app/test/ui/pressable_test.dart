import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';

void main() {
  testWidgets('a finger lifted after its card has left the screen is not an error', (tester) async {
    // A drag that starts on a card can outlive it: the list rebuilds, a tab
    // closes. The card still hears the finger lift (the gesture keeps its
    // target), and must not touch a state that is gone.
    final show = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (_, on, _) => Center(
          child: on
              ? const Pressable(shape: RoundedRectangleBorder(), child: SizedBox(width: 200, height: 80, child: Text('card')))
              : const SizedBox.shrink(),
        ),
      ),
    ));
    final finger = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    show.value = false;
    await tester.pump();
    await finger.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
