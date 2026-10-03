import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack_doctor/patients.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
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

  // A share with a LifeTrack ID stands for one whose ID the registry
  // confirmed; one without is filed under its reply key.
  ReceivedShare share(String name, {String? ltId, String mailbox = 'p-abc', DateTime? at, int age = 42}) => ReceivedShare(
        grantId: 'g-$name-${at?.millisecondsSinceEpoch}',
        bundle: {
          'patient': {'name': name, 'age': age, 'sex': 'female', 'lifeTrackId': ?ltId},
          'replyTo': {'mailbox': mailbox, 'key': 'key-of-$mailbox'},
          'levels': ['summary'],
        },
        expiresAt: (at ?? DateTime(2026, 10, 1)).add(const Duration(hours: 24)),
        receivedAt: at ?? DateTime(2026, 10, 1),
        verified: ltId != null,
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

  test('the register: one entry per person across shares, keyed by confirmed LifeTrack ID, else reply key', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    final s = await DoctorSession.load(base, cipher: MemoryCipher());
    s.registerShare(share('Anjali Sharma', ltId: '148209375516', at: DateTime(2026, 9, 1)));
    s.registerShare(share('Anjali Sharma', ltId: '148209375516', mailbox: 'p-new', at: DateTime(2026, 10, 1), age: 43));
    s.registerShare(share('Ramesh Kumar', mailbox: 'p-ramesh', at: DateTime(2026, 9, 15)));
    expect(s.patients.map((p) => p.name), ['Anjali Sharma', 'Ramesh Kumar (identity not confirmed)'], reason: 'most recent first');
    final a = s.patients.first;
    expect([a.shares, a.age, a.firstSeen, a.lastShared], [2, 43, DateTime(2026, 9, 1), DateTime(2026, 10, 1)]);
    expect(s.patients.last.key, 'key:${ReceivedShare.keyTag('key-of-p-ramesh')}');
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

  group('shares from someone pretending to be a patient', () {
    Future<String> sealTo(DoctorSession s, Map<String, Object?> bundle, String gid) async => base64Encode(await ShareEnvelope.seal(
          bundle: bundle,
          recipientKey: (await s.enc!.extractPublicKey()).bytes,
          keyId: await RelayApi.keyId((await s.enc!.extractPublicKey()).bytes),
          grantId: gid,
          expiresAt: DateTime.now().add(const Duration(hours: 4)),
        ));

    test("a share naming someone's LifeTrack ID, that the registry cannot confirm, is filed apart and marked", () async {
      SharedPreferences.setMockInitialValues(await legacyPrefs());
      final s = await DoctorSession.load(base, cipher: MemoryCipher());
      final real = share('Anjali Sharma', ltId: '148209375516');
      s.inbox.add(real);
      s.registerShare(real);
      final forged = await sealTo(s, {
        'patient': {'name': 'Anjali Sharma', 'age': 42, 'sex': 'female', 'lifeTrackId': '148209375516'},
        'replyTo': {'mailbox': 'p-${'e' * 64}', 'key': base64Encode(List.filled(32, 7))},
        'levels': ['summary'],
      }, 'g-forged');
      expect(await s.receive(forged, DateTime.now()), isTrue);
      final f = s.inbox.first;
      expect(f.verified, isFalse);
      expect(f.lifeTrackId, isNull);
      expect(f.patientName, 'Anjali Sharma (identity not confirmed)');
      expect(s.openShareFor('148209375516'), same(real), reason: "the real patient's open share is untouched");
      expect(s.patients.where((p) => p.key == '148209375516').single.name, 'Anjali Sharma');
      expect(s.patients, hasLength(2));
    });

    test('an envelope that cannot be opened is refused on its own', () async {
      SharedPreferences.setMockInitialValues(await legacyPrefs());
      final s = await DoctorSession.load(base, cipher: MemoryCipher());
      await expectLater(s.receive(base64Encode(utf8.encode('not an envelope')), DateTime.now()), throwsA(anything));
      final other = await X25519().newKeyPair();
      final notMine = base64Encode(await ShareEnvelope.seal(
          bundle: {'patient': {'name': 'X'}, 'replyTo': {'mailbox': 'p-x', 'key': 'k'}},
          recipientKey: (await other.extractPublicKey()).bytes,
          keyId: 'k',
          grantId: 'g',
          expiresAt: DateTime.now().add(const Duration(hours: 1))));
      await expectLater(s.receive(notMine, DateTime.now()), throwsA(anything));
      final ok = await sealTo(s, {'patient': {'name': 'Ramesh Kumar'}, 'replyTo': {'mailbox': 'p-r', 'key': 'kr'}}, 'g-ok');
      expect(await s.receive(ok, DateTime.now()), isTrue);
      expect(s.inbox, hasLength(1));
    });

    test("a close message without the patient's secret closes nothing", () async {
      SharedPreferences.setMockInitialValues(await legacyPrefs());
      final s = await DoctorSession.load(base, cipher: MemoryCipher());
      final real = share('Anjali Sharma', ltId: '148209375516');
      s.inbox.add(real);
      expect(await s.receive(await sealTo(s, {'type': 'close', 'grantId': real.grantId}, 'c1'), DateTime.now()), isFalse);
      expect(await s.receive(await sealTo(s, {'type': 'close', 'grantId': real.grantId, 'closeSecret': 'guess'}, 'c2'), DateTime.now()), isFalse);
      expect(s.inbox, [real]);
    });

    test("copying a patient's real ID and registered key from the public lookup is not enough", () async {
      SharedPreferences.setMockInitialValues(await legacyPrefs());
      // The patient's phone: its reply key is what the registry has on the ID.
      final reply = await X25519().newKeyPair();
      final replyKey = base64Encode((await reply.extractPublicKey()).bytes);
      final id = LifeTrackId.generate();
      final registry = MockClient((r) async => r.url.path == '/v1/ids/$id'
          ? http.Response(jsonEncode({'id': id, 'mailbox': 'p-${'a' * 64}', 'key': replyKey}), 200)
          : http.Response('{}', 404));
      final s = await DoctorSession.load(base, cipher: MemoryCipher(), client: registry);
      final doctorKey = (await s.enc!.extractPublicKey()).bytes;
      Map<String, Object?> bundle(String? proof) => {
            'patient': {'name': 'Anjali Sharma', 'lifeTrackId': id},
            'replyTo': {'mailbox': 'p-${'a' * 64}', 'key': replyKey},
            'senderProof': ?proof,
          };

      // A forger has the ID and the key (both public), but not the reply
      // private key: no proof, a proof from their own key, or one made for
      // another grant.
      final mine = await X25519().newKeyPair();
      final ownKey = await SenderProof.make(replyKeyPair: mine, doctorKey: doctorKey, grantId: 'g1', lifeTrackId: id);
      final otherGrant = await SenderProof.make(replyKeyPair: reply, doctorKey: doctorKey, grantId: 'g-other', lifeTrackId: id);
      for (final (i, proof) in [null, ownKey, otherGrant, 'not base64!'].indexed) {
        await s.receive(await sealTo(s, bundle(proof), 'g1'), DateTime.now());
        expect(s.inbox.first.verified, isFalse, reason: 'forgery $i');
      }

      // The patient's own phone proves it holds the key.
      final real = await SenderProof.make(replyKeyPair: reply, doctorKey: doctorKey, grantId: 'g2', lifeTrackId: id);
      await s.receive(await sealTo(s, bundle(real), 'g2'), DateTime.now());
      expect(s.inbox.first.verified, isTrue);
      expect(s.inbox.first.lifeTrackId, id);
    });
  });

  test('a revoked device stays revoked after a restart, and drops its certificate', () async {
    SharedPreferences.setMockInitialValues(await legacyPrefs());
    final registry = MockClient((r) async => http.Response(jsonEncode({'status': 'revoked', 'note': 'Licence suspended.'}), 200));
    final cipher = MemoryCipher();
    final s = await DoctorSession.load(base, cipher: cipher, client: registry);
    expect(s.state, EnrolmentState.approved);
    await s.refreshStatus();
    expect(s.state, EnrolmentState.revoked);
    expect(s.certificateQr, isNull);

    final again = await DoctorSession.load(base, cipher: cipher);
    expect(again.state, EnrolmentState.revoked);
    expect(again.certificateQr, isNull);
    expect(again.note, 'Licence suspended.');
  });

  testWidgets('demo builds can fill the app with sample patients, which survive a reload and replace themselves', (tester) async {
    late DoctorSession s;
    final cipher = MemoryCipher();
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(await legacyPrefs());
      s = await DoctorSession.load(base, cipher: cipher);
      final real = share('Anjali Sharma', ltId: '148209375516');
      s.inbox.add(real);
      s.registerShare(real);
      await expectLater(s.addSamplePatients(DateTime.now()), throwsStateError, reason: 'not a demo build');
      await s.addSamplePatients(DateTime.now(), allowed: true);
      await s.addSamplePatients(DateTime.now(), allowed: true);
    });
    expect(s.patients, hasLength(7), reason: 'six samples once each, and the real patient kept');
    expect(s.inbox.where((x) => x.patientName.endsWith('(sample)')), hasLength(3));
    expect(s.inbox.every((x) => x.verified), isTrue);
    expect(s.prescriptions, hasLength(6));
    expect(s.notes, hasLength(4));
    expect(s.patients.where((p) => p.name == 'Anjali Sharma'), hasLength(1));

    await tester.runAsync(() async {
      final again = await DoctorSession.load(base, cipher: cipher);
      expect(again.inbox.where((x) => x.patientName.endsWith('(sample)')), hasLength(3), reason: 'open sample shares re-open after a restart');
      expect(again.prescriptions, hasLength(6));
    });

    // Each open sample renders as a patient page.
    for (final sh in s.inbox.where((x) => x.patientName.endsWith('(sample)'))) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PatientScreen(session: s, patientKey: sh.patientKey, onClose: () {}, onChanged: () {}))));
      expect(find.textContaining(sh.patientName), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
