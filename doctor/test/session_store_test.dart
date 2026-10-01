import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/patients.dart';
import 'package:lifetrack_doctor/practice.dart';
import 'package:lifetrack_doctor/session.dart';
import 'package:lifetrack_doctor/store/memory_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final base = Uri.parse('http://127.0.0.1:1');

  Future<Map<String, Object>> legacyPrefs() async {
    final e = await X25519().newKeyPair();
    final s = await Ed25519().newKeyPair();
    return {
      'flutter.lt.doctor.enc': base64Encode(await e.extractPrivateKeyBytes()),
      'flutter.lt.doctor.sign': base64Encode(await s.extractPrivateKeyBytes()),
      'flutter.lt.doctor.profile': jsonEncode({'name': 'Dr. Priya Nair', 'speciality': 'Endocrinology', 'council': 'Delhi Medical Council', 'registrationNo': 'DMC-67890'}),
      'flutter.lt.doctor.cert': 'CERT-QR-TEXT',
    };
  }

  ReceivedShare share(String name, {String? ltId, String mailbox = 'p-abc', DateTime? at, int age = 42}) => ReceivedShare(
        grantId: 'g-$name-${at?.millisecondsSinceEpoch}',
        bundle: {
          'patient': {'name': name, 'age': age, 'sex': 'female', 'lifeTrackId': ?ltId},
          'replyTo': {'mailbox': mailbox, 'key': ''},
          'levels': ['summary'],
        },
        expiresAt: (at ?? DateTime(2026, 10, 1)).add(const Duration(hours: 24)),
        receivedAt: at ?? DateTime(2026, 10, 1),
      );

  test('keys and profile saved in the clear by an older version are sealed on load', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    final cipher = MemoryCipher();
    final s = await DoctorSession.load(base, cipher: cipher);
    expect(s.state, EnrolmentState.approved);
    expect(s.profile['name'], 'Dr. Priya Nair');
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k)!;
      expect(v, startsWith('lt1:'), reason: k);
      expect(v.contains('Priya'), isFalse);
    }
    final again = await DoctorSession.load(base, cipher: cipher);
    expect(again.certificateQr, 'CERT-QR-TEXT', reason: 'reopens with the same browser key');
  });

  test('without this browser\'s key, nothing opens', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    await DoctorSession.load(base, cipher: MemoryCipher());
    final other = await DoctorSession.load(base, cipher: MemoryCipher(SecretKey(List.filled(32, 9))));
    expect(other.state, EnrolmentState.none);
    expect(other.enc, isNull);
  });

  test('the register: one entry per person across shares, keyed by LifeTrack ID, else mailbox', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    final s = await DoctorSession.load(base, cipher: MemoryCipher());
    s.registerShare(share('Anjali Sharma', ltId: '148209375516', at: DateTime(2026, 9, 1)));
    s.registerShare(share('Anjali Sharma', ltId: '148209375516', mailbox: 'p-new', at: DateTime(2026, 10, 1), age: 43));
    s.registerShare(share('Ramesh Kumar', mailbox: 'p-ramesh', at: DateTime(2026, 9, 15)));
    expect(s.patients.map((p) => p.name), ['Anjali Sharma', 'Ramesh Kumar'], reason: 'most recent first');
    final a = s.patients.first;
    expect([a.shares, a.age, a.firstSeen, a.lastShared], [2, 43, DateTime(2026, 9, 1), DateTime(2026, 10, 1)]);
    expect(s.patients.last.key, 'p-ramesh');
  });

  test('notes are sealed, survive a reload, and can be edited and deleted', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    final cipher = MemoryCipher();
    final s = await DoctorSession.load(base, cipher: cipher);
    final n = ConsultNote(id: 'n1', patientKey: 'k', at: DateTime(2026, 10, 1, 11), complaint: 'Tiredness', advice: 'Walk daily', followUp: DateTime(2026, 10, 15));
    await s.saveNote(n);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lt.doctor.notes'), startsWith('lt1:'));
    expect(prefs.getString('lt.doctor.notes')!.contains('Tiredness'), isFalse);

    final again = await DoctorSession.load(base, cipher: cipher);
    expect(again.notesFor('k').single.advice, 'Walk daily');
    expect(nextFollowUp(again, 'k', DateTime(2026, 10, 2)), DateTime(2026, 10, 15));
    expect(nextFollowUp(again, 'k', DateTime(2026, 10, 16)), isNull, reason: 'past follow-ups are not shown as due');

    await again.saveNote(ConsultNote(id: 'n1', patientKey: 'k', at: n.at, complaint: 'Tiredness, better'));
    expect(again.notesFor('k').single.complaint, 'Tiredness, better');
    await again.deleteNote('n1');
    expect((await DoctorSession.load(base, cipher: cipher)).notesFor('k'), isEmpty);
    expect(() => again.saveNote(ConsultNote(id: 'x', patientKey: 'k', at: n.at, complaint: 'a' * 2001)), throwsArgumentError);
  });

  testWidgets('My patients lists the register; a closed patient offers to ask again; notes can be added', (tester) async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    late DoctorSession s;
    await tester.runAsync(() async {
      s = await DoctorSession.load(base, cipher: MemoryCipher());
      s.registerShare(share('Anjali Sharma', ltId: '148209375516', at: DateTime(2026, 9, 1)));
    });
    tester.view.physicalSize = const Size(400 * 2.6, 860 * 2.6);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    String? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PatientsTab(session: s, onOpen: (k) => opened = k, onChanged: () {}))));
    expect(find.text('All patients · 1'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Anjali Sharma · F · 42 y'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Anjali Sharma · F · 42 y'));
    expect(opened, '148209375516');

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PatientScreen(session: s, patientKey: '148209375516', onClose: () {}, onChanged: () {}))));
    expect(find.text('Their shared records are closed'), findsOneWidget);
    expect(find.text('Ask for access again'), findsOneWidget);
    expect(find.text('LifeTrack ID 1482 0937 5516'), findsOneWidget);

    await tester.ensureVisible(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Follow-up for diabetes');
    await tester.ensureVisible(find.text('Save note'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save note'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(s.notesFor('148209375516').single.complaint, 'Follow-up for diabetes');
  });
}
