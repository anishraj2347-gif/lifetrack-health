import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/patients.dart';
import 'package:lifetrack_doctor/session.dart';
import 'package:lifetrack_doctor/store/memory_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<DoctorSession> session() async {
    final e = await X25519().newKeyPair();
    final s = await Ed25519().newKeyPair();
    SharedPreferences.setMockInitialValues({
      'flutter.lt.doctor.enc': base64Encode(await e.extractPrivateKeyBytes()),
      'flutter.lt.doctor.sign': base64Encode(await s.extractPrivateKeyBytes()),
      'flutter.lt.doctor.profile': jsonEncode({'name': 'Dr. Priya Nair', 'registrationNo': 'DMC-67890'}),
      'flutter.lt.doctor.cert': 'CERT-QR-TEXT',
    });
    return DoctorSession.load(Uri.parse('http://127.0.0.1:1'), cipher: MemoryCipher());
  }

  final share = ReceivedShare(
    grantId: 'g',
    bundle: {
      'patient': {'name': 'Anjali Sharma', 'age': 42, 'sex': 'female'},
      'replyTo': {'mailbox': 'p-a', 'key': 'k'},
      'levels': ['summary'],
    },
    expiresAt: DateTime(2026, 10, 2),
    receivedAt: DateTime(2026, 10, 1),
    verified: false,
  );

  Future<void> pump(WidgetTester t, DoctorSession s) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PrescribeCard(session: s, share: share, onSent: () {})))));
  }

  Finder slot(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
  TextField field(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint).evaluate().single.widget as TextField;

  testWidgets('a new prescription carries no dose, course or food timing until the doctor sets them', (t) async {
    final s = (await t.runAsync(session))!;
    await pump(t, s);
    expect(slot('Morning 0'), findsOneWidget);
    expect(slot('Afternoon 0'), findsOneWidget);
    expect(slot('Night 0'), findsOneWidget);
    expect(field('e.g. 14').controller!.text, isEmpty);
    final chips = t.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(chips.where((c) => c.selected).map((c) => (c.label as Text).data), ['Any time']);
  });

  testWidgets('it will not send until the course and a dose are set', (t) async {
    final s = (await t.runAsync(session))!;
    await pump(t, s);
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'e.g. Atorvastatin 10 mg'), 'Atorvastatin 10 mg');
    await t.tap(find.text('Sign and send'));
    await t.pump();
    expect(find.textContaining('Days must be a number'), findsOneWidget);
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'e.g. 14'), '30');
    await t.tap(find.text('Sign and send'));
    await t.pump();
    expect(find.text('Set at least one dose.'), findsOneWidget);
  });
}
