import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteNames;
import '../../model/health_record.dart';
import '../../security/plain_leftovers.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'records_screen.dart' show kindLabel;

/// Photograph a paper report or prescription — most in India are paper.
///
/// The photo IS the record a doctor trusts; the patient only confirms a few
/// facts (what it is, which lab, when) and may skip the values. Nothing is
/// read out of the photo automatically yet.
class ScanReportScreen extends StatefulWidget {
  const ScanReportScreen({super.key});
  @override
  State<ScanReportScreen> createState() => _ScanReportScreenState();
}

class _Value {
  String? analyte;
  final value = TextEditingController();
  final unit = TextEditingController();
  final low = TextEditingController();
  final high = TextEditingController();
}

class _ScanReportScreenState extends State<ScanReportScreen> {
  final _picker = ImagePicker();
  final List<Uint8List> _pages = [];
  bool _details = false;
  bool _saving = false;
  String? _error;

  RecordKind _kind = RecordKind.report;
  final _title = TextEditingController();
  final _lab = TextEditingController();
  final _doctor = TextEditingController();
  DateTime? _sampled;
  final List<_Value> _values = [];

  static const _commonReports = ['Complete blood count', 'Lipid panel', 'HbA1c', 'Fasting glucose', 'Thyroid profile', 'Liver function', 'Kidney function', 'Urine routine'];

  Future<void> _camera() async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    if (x != null) {
      final b = await x.readAsBytes();
      // The camera's file is a plain copy with location data; only the
      // cleaned, encrypted page is kept.
      await deleteQuietly(x.path);
      setState(() => _pages.add(b));
    }
  }

  bool _fromPdf = false;
  bool _converting = false;

  /// A PDF the lab sent: each page becomes an image, then goes through the
  /// same clean-and-encrypt path as a photo. At most 12 pages.
  Future<void> _pdf() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (files.isEmpty) return;
    final bytes = await files.first.xFile.readAsBytes();
    // The picker's plain copy in the cache is not needed once read.
    await deleteQuietly(files.first.path);
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'That PDF is over 25 MB. Ask the lab for the report alone.');
      return;
    }
    setState(() {
      _converting = true;
      _error = null;
    });
    try {
      var n = 0;
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        if (n++ >= 12) break;
        _pages.add(await page.toPng());
      }
      _fromPdf = true;
    } on Object {
      _error = 'This PDF could not be opened. If it has a password, open it once in another app and save a copy without one.';
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _gallery() async {
    final xs = await _picker.pickMultiImage();
    for (final x in xs) {
      _pages.add(await x.readAsBytes());
    }
    setState(() {});
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Say what this is, e.g. Lipid panel.');
      return;
    }
    final results = <LabResult>[];
    for (final v in _values) {
      final n = double.tryParse(v.value.text.trim());
      if (v.analyte == null || n == null || v.unit.text.trim().isEmpty) continue;
      results.add(LabResult(
        analyte: v.analyte!,
        value: n,
        unit: v.unit.text.trim(),
        printedLow: double.tryParse(v.low.text.trim()),
        printedHigh: double.tryParse(v.high.text.trim()),
      ));
    }
    setState(() => _saving = true);
    try {
      final rng = Random.secure();
      await s.addScanned(
        rawPages: _pages,
        draft: HealthRecord(
          id: 'r-${List.generate(8, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
          patientId: s.currentPatientId!,
          kind: _kind,
          title: _title.text.trim(),
          date: _sampled ?? DateTime.now(),
          sampleDate: _kind == RecordKind.report ? _sampled : null,
          source: RecordSource.smartCapture,
          originalFormat: _fromPdf ? 'pdf' : null,
          labName: _lab.text.trim().isEmpty ? null : _lab.text.trim(),
          facility: _lab.text.trim().isEmpty ? null : _lab.text.trim(),
          doctor: _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
          results: results,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: _details ? _form() : _capture());

  Widget _capture() => ListView(children: [
        Masthead(
          eyebrow: 'Add a paper report',
          title: 'Photograph every page',
          description: 'The photo is kept for your doctor. Location and camera details are removed; it stays encrypted on this phone.',
        ),
        SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: SlabButton('Camera', icon: LucideIcons.camera, onPressed: _camera)),
            SizedBox(width: 10),
            Expanded(child: SlabButton('From photos', icon: LucideIcons.images, variant: ButtonVariant.outline, onPressed: _gallery)),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SlabButton(_converting ? 'Opening the PDF…' : 'From a PDF the lab sent', icon: LucideIcons.fileText, variant: ButtonVariant.outline, onPressed: _converting ? null : _pdf),
        ),
        if (_error != null && !_details) Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        SizedBox(height: 16),
        if (_pages.isEmpty)
          Note('Tip: lay the report flat in good light, fill the frame, one photo per page. A WhatsApp photo of a report works too.', icon: LucideIcons.lightbulb)
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [
                for (final (i, p) in _pages.indexed)
                  Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(p, fit: BoxFit.cover, cacheWidth: 300)),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Badge2('Page ${i + 1}'),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Remove page ${i + 1}',
                        icon: Icon(LucideIcons.x, size: 16),
                        onPressed: () => setState(() => _pages.removeAt(i)),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(
            _pages.isEmpty ? 'Add at least one page' : 'Next · ${_pages.length} page${_pages.length == 1 ? '' : 's'}',
            onPressed: _pages.isEmpty ? null : () => setState(() => _details = true),
          ),
        ),
      ]);

  Widget _form() => ListView(children: [
        Masthead(eyebrow: 'Add a paper report', title: 'What is it?', description: 'Only what is printed on it. You can skip the values — the photo carries them.'),
        SizedBox(
          height: 110,
          child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.fromLTRB(16, 12, 16, 0), children: [
            for (final p in _pages)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(p, width: 70, fit: BoxFit.cover, cacheWidth: 200)),
              ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in [RecordKind.report, RecordKind.prescription, RecordKind.scan])
              Chip2(kindLabel(k), selected: _kind == k, onTap: () => setState(() => _kind = k)),
          ]),
        ),
        LabeledField(label: _kind == RecordKind.prescription ? 'Medicine or title' : 'Report name', child: TextField(controller: _title)),
        if (_kind == RecordKind.report)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _commonReports) Chip2(c, selected: _title.text == c, onTap: () => setState(() => _title.text = c)),
            ]),
          ),
        LabeledField(
          label: _kind == RecordKind.prescription ? 'Clinic or hospital' : 'Lab name, as printed',
          child: TextField(controller: _lab, decoration: InputDecoration(hintText: 'e.g. Thyrocare, Dr Lal PathLabs')),
        ),
        if (_kind == RecordKind.prescription) LabeledField(label: 'Doctor', child: TextField(controller: _doctor)),
        LabeledField(
          label: _kind == RecordKind.report ? 'Date the sample was taken' : 'Date on the document',
          hint: 'This is what tells a doctor how recent the result is.',
          child: FieldButton(
            text: _sampled == null ? 'Pick the date printed on it' : fullDate(_sampled!),
            placeholder: _sampled == null,
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime.now());
              if (d != null) setState(() => _sampled = d);
            },
          ),
        ),
        if (_kind == RecordKind.report) ...[
          Eyebrow('Key values (optional)'),
          for (final v in _values)
            ShadCard(
              child: Column(children: [
                DropdownButtonFormField<String>(
                  initialValue: v.analyte,
                  isExpanded: true,
                  hint: Text('Which test'),
                  items: [for (final e in analyteNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (x) => setState(() => v.analyte = x),
                ),
                SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: v.value, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Result'))),
                  SizedBox(width: 8),
                  Expanded(child: TextField(controller: v.unit, decoration: InputDecoration(hintText: 'Unit'))),
                ]),
                SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: v.low, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Lab range from'))),
                  SizedBox(width: 8),
                  Expanded(child: TextField(controller: v.high, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'to'))),
                ]),
              ]),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: SlabButton('Add a value', variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => setState(() => _values.add(_Value()))),
          ),
        ],
        if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(_saving ? 'Saving…' : 'Save report', icon: LucideIcons.check, onPressed: _saving ? null : _save),
        ),
      ]);
}
