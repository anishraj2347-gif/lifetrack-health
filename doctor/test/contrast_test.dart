import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/patients.dart';
import 'package:lifetrack_doctor/practice.dart';
import 'package:lifetrack_doctor/session.dart';
import 'package:lifetrack_doctor/store/memory_cipher.dart';
import 'package:lifetrack_doctor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contrast_check.dart';

/// Doctor app: every text readable on its background (see contrast_check.dart).
void main() {
  for (final mode in ['light', 'dark']) {
    testWidgets(
      '$mode: patients, a patient (open and closed), prescriptions, my code',
      (tester) async {
        DT.dark = mode == 'dark';
        addTearDown(() => DT.dark = false);
        final e = await X25519().newKeyPair();
        final sg = await Ed25519().newKeyPair();
        SharedPreferences.setMockInitialValues({
          'flutter.lt.doctor.enc': base64Encode(
            await e.extractPrivateKeyBytes(),
          ),
          'flutter.lt.doctor.sign': base64Encode(
            await sg.extractPrivateKeyBytes(),
          ),
          'flutter.lt.doctor.profile': jsonEncode({
            'name': 'Dr. Priya Nair',
            'speciality': 'Endocrinology',
            'council': 'Delhi Medical Council',
            'registrationNo': 'DMC-67890',
          }),
          'flutter.lt.doctor.cert': 'CERT',
        });
        late DoctorSession s;
        final now = DateTime.now();
        await tester.runAsync(() async {
          s = await DoctorSession.load(
            Uri.parse('http://127.0.0.1:1'),
            cipher: MemoryCipher(),
          );
          final open = ReceivedShare(
            grantId: 'g1',
            bundle: {
              'patient': {
                'name': 'Anjali Sharma',
                'age': 42,
                'sex': 'female',
                'lifeTrackId': '156344947162',
              },
              'replyTo': {'mailbox': 'p-a', 'key': ''},
              'levels': ['summary'],
              'allergies': [
                {'substance': 'Penicillin', 'reaction': 'rash'},
              ],
              'conditions': [],
              'medicines': {'active': [], 'endedRecently': []},
              'latestTests': [],
            },
            expiresAt: now.add(const Duration(hours: 4)),
            receivedAt: now,
            verified: true,
          );
          s.inbox.add(open);
          s.registerShare(open);
          s.registerShare(
            ReceivedShare(
              grantId: 'g2',
              bundle: {
                'patient': {
                  'name': 'Ramesh Kumar',
                  'age': 66,
                  'sex': 'male',
                  'lifeTrackId': '148209375516',
                },
                'replyTo': {'mailbox': 'p-r'},
                'levels': ['summary'],
              },
              expiresAt: now.subtract(const Duration(days: 1)),
              receivedAt: now.subtract(const Duration(days: 3)),
              verified: true,
            ),
          );
          await s.saveNote(
            ConsultNote(
              id: 'n',
              patientKey: '148209375516',
              at: now,
              complaint: 'Knee pain',
              followUp: now.add(const Duration(days: 7)),
            ),
          );
        });
        tester.view.physicalSize = const Size(400 * 2.6, 860 * 2.6);
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);

        Future<void> show(String name, Widget w) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: DT.theme(),
              home: Scaffold(backgroundColor: DT.ground, body: w),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            lowContrastTexts(tester, page: DT.ground),
            isEmpty,
            reason: '$mode · $name',
          );
        }

        await show(
          'My patients',
          PatientsTab(session: s, onOpen: (_) {}, onChanged: () {}),
        );
        await show(
          'Open patient',
          PatientScreen(
            session: s,
            patientKey: '156344947162',
            onClose: () {},
            onChanged: () {},
          ),
        );
        await show(
          'Closed patient',
          PatientScreen(
            session: s,
            patientKey: '148209375516',
            onClose: () {},
            onChanged: () {},
          ),
        );
        await show(
          'Prescriptions',
          PrescriptionsTab(
            session: s,
            onOpenPatient: (_) {},
            onWriteAgain: (_) {},
          ),
        );
        await show('My code', MyCodePanel(session: s));
      },
    );
  }
}
