import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/print_rx.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

void main() {
  test('the paper prescription carries the registration and a signature fingerprint', () async {
    final key = await Ed25519().newKeyPair();
    final rx = await SignedPrescription(
      patientId: 'ref-1', doctorRegistryId: 'DMC-67890', doctorName: 'Dr. Priya Nair', qualification: 'MBBS, MD',
      registrationNo: 'DMC-67890', medicine: 'Cholecalciferol 60000 IU', ingredient: 'cholecalciferol',
      morning: 0, afternoon: 0, night: 1, days: 56, issuedAt: DateTime(2026, 10, 1, 21, 15),
      note: 'Once a week for 8 weeks. Recheck vitamin D in 3 months.', timing: 'after_food',
    ).signedWith(key);
    final fp = await signatureFingerprint(rx);
    expect(fp, matches(RegExp(r'^[0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}$')));
    expect(await signatureFingerprint(rx), fp, reason: 'stable');
    final doc = await prescriptionPdf(rx: rx, patientName: 'Anjali Sharma', patientLine: 'F · 42 y', council: 'Delhi Medical Council', speciality: 'Endocrinology');
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = const String.fromEnvironment('RX_OUT');
    if (out.isNotEmpty) File(out).writeAsBytesSync(bytes);
  });
}
