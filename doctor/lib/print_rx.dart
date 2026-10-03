import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const _timings = {'before_food': 'Before food', 'after_food': 'After food', 'with_food': 'With food'};

/// A short, readable fingerprint of the prescription's signature, so the
/// paper copy can be matched to the signed one on the patient's phone.
Future<String> signatureFingerprint(SignedPrescription rx) async {
  final h = await Sha256().hash(rx.signature);
  final hex = h.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join(' ');
}

/// The paper prescription: what the Telemedicine Practice Guidelines 2020
/// expect on one — the doctor's name, qualification and registration number,
/// the patient, the medicine with dose and duration, the date — plus the
/// fingerprint of the digital signature it was sent with.
Future<pw.Document> prescriptionPdf({
  required SignedPrescription rx,
  required String patientName,
  required String patientLine,
  required String council,
  required String speciality,
  List<String> practice = const [],
}) async {
  final fp = await signatureFingerprint(rx);
  final issued = rx.issuedAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(issued.day)}/${two(issued.month)}/${issued.year} ${two(issued.hour)}:${two(issued.minute)}';
  final doc = pw.Document(title: 'Prescription — $patientName', author: rx.doctorName);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(28),
    build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(rx.doctorName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('${rx.qualification}${speciality.isEmpty ? '' : ' · $speciality'}', style: const pw.TextStyle(fontSize: 10)),
      pw.Text('Reg. no. ${rx.registrationNo} · $council', style: const pw.TextStyle(fontSize: 10)),
      // Clinic, address and phone, from Profile → Practice details.
      for (final line in practice) pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
      pw.Divider(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Patient: $patientName  $patientLine', style: const pw.TextStyle(fontSize: 11)),
        pw.Text(date, style: const pw.TextStyle(fontSize: 10)),
      ]),
      pw.SizedBox(height: 16),
      pw.Text('Rx', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Text(rx.medicine, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (rx.ingredient != null) pw.Text('(${rx.ingredient})', style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 6),
      pw.Text(
        'Dose ${rx.morning}-${rx.afternoon}-${rx.night} (morning-afternoon-night)'
        '${rx.timing == null ? '' : ' · ${_timings[rx.timing]}'} · for ${rx.days} days',
        style: const pw.TextStyle(fontSize: 11),
      ),
      if (rx.note != null && rx.note!.trim().isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Instructions: ${rx.note!.trim()}', style: const pw.TextStyle(fontSize: 11)),
      ],
      pw.Spacer(),
      pw.Divider(),
      pw.Text('Digitally signed and sent to the patient through LifeTrack.', style: const pw.TextStyle(fontSize: 8)),
      pw.Text('Signature fingerprint: $fp. It matches the signed copy in the patient\'s LifeTrack app.', style: const pw.TextStyle(fontSize: 8)),
    ]),
  ));
  return doc;
}

/// Opens the browser's print dialog (print, or save as PDF).
Future<void> printPrescription({
  required SignedPrescription rx,
  required String patientName,
  required String patientLine,
  required String council,
  required String speciality,
  List<String> practice = const [],
}) async {
  final doc = await prescriptionPdf(rx: rx, patientName: patientName, patientLine: patientLine, council: council, speciality: speciality, practice: practice);
  await Printing.layoutPdf(name: 'Prescription ${rx.registrationNo} $patientName.pdf', onLayout: (_) => doc.save());
}
