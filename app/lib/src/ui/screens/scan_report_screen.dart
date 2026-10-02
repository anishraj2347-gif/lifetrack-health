import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteNames;
import '../../ai/plane_b/capture.dart';
import '../../capture/incoming_files.dart';
import '../../model/health_record.dart';
import '../../security/plain_leftovers.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'records_screen.dart' show kindLabel;

/// Add a report, prescription or scan from any source — camera, photos, a
/// PDF, or shared from another app — and LifeTrack reads it on the phone.
///
/// The photo IS the record a doctor trusts. What is read off it is a draft:
/// anything LifeTrack is unsure of is highlighted and must be ticked or
/// corrected, then the patient confirms the whole draft against the photo.
/// Nothing is saved before that.
class ScanReportScreen extends StatefulWidget {
  const ScanReportScreen({super.key, this.incoming = const []});

  /// Files shared to LifeTrack from another app.
  final List<IncomingFile> incoming;

  @override
  State<ScanReportScreen> createState() => _ScanReportScreenState();
}

/// A field the scan filled but was unsure of: it waits for the patient.
class _Check {
  _Check(DraftField<Object?> f) : needed = f.value != null && f.uncertain, seen = f.seen;
  _Check.manual() : needed = false, seen = null;
  final bool needed;
  final String? seen;
  bool done = false;
  bool edited = false;
  bool get ok => !needed || done;
}

class _Value {
  _Value([DraftField<LabResult>? f]) : check = f == null ? _Check.manual() : _Check(f) {
    final r = f?.value;
    if (r == null) return;
    analyte = r.analyte;
    value.text = _num(r.value);
    unit.text = r.unit;
    if (r.printedLow != null) low.text = _num(r.printedLow!);
    if (r.printedHigh != null) high.text = _num(r.printedHigh!);
  }
  final _Check check;
  String? analyte;
  final value = TextEditingController();
  final unit = TextEditingController();
  final low = TextEditingController();
  final high = TextEditingController();
}

class _Medicine {
  _Medicine([DraftMedicine? m])
      : check = m == null ? _Check.manual() : _Check(_worst(m)),
        timing = m?.timing.value {
    name.text = m?.name.value ?? '';
    if (m?.dose.value case final d?) dose = [d.morning, d.afternoon, d.night];
    if (m?.days.value case final n?) days.text = '$n';
  }
  final _Check check;
  final name = TextEditingController();
  List<int> dose = [1, 0, 1];
  String? timing;
  final days = TextEditingController();

  /// One tick per medicine: it stands for its least certain part.
  static DraftField<Object?> _worst(DraftMedicine m) {
    final parts = <DraftField<Object?>>[m.name, if (m.dose.value != null) m.dose else const DraftField<Object?>(null, confidence: 0.5), if (m.timing.value != null) m.timing, if (m.days.value != null) m.days];
    final c = parts.map((p) => p.confidence).reduce(min);
    return DraftField(m.name.value, confidence: c, seen: m.name.seen);
  }
}

String _num(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : '$x';

enum _Step { capture, reading, review }

class _ScanReportScreenState extends State<ScanReportScreen> {
  final _picker = ImagePicker();
  final List<Uint8List> _pages = [];
  _Step _step = _Step.capture;
  bool _saving = false;
  String? _error;
  bool _fromPdf = false;
  bool _converting = false;
  String _progress = '';

  CaptureDraft _draft = CaptureDraft.empty;
  bool _readFailed = false;
  RecordKind _kind = RecordKind.report;
  _Check _kindCheck = _Check.manual();
  final _title = TextEditingController();
  _Check _titleCheck = _Check.manual();
  final _place = TextEditingController();
  _Check _placeCheck = _Check.manual();
  final _doctor = TextEditingController();
  _Check _doctorCheck = _Check.manual();
  DateTime? _date;
  _Check _dateCheck = _Check.manual();
  final List<_Value> _values = [];
  final List<_Medicine> _medicines = [];

  static const _commonReports = ['Complete blood count', 'Lipid panel', 'HbA1c', 'Fasting glucose', 'Thyroid profile', 'Liver function', 'Kidney function', 'Urine routine'];

  @override
  void initState() {
    super.initState();
    if (widget.incoming.isNotEmpty) _takeIncoming();
  }

  Future<void> _takeIncoming() async {
    for (final f in widget.incoming) {
      if (f.mime == 'application/pdf') {
        await _addPdf(f.bytes);
      } else {
        _pages.add(f.bytes);
      }
    }
    if (mounted) setState(() {});
  }

  // ---- getting the pages ---------------------------------------------------

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

  Future<void> _gallery() async {
    final xs = await _picker.pickMultiImage();
    for (final x in xs) {
      _pages.add(await x.readAsBytes());
    }
    setState(() {});
  }

  /// Any photo or PDF on the phone or in a cloud drive the file picker shows.
  Future<void> _file() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic']);
    for (final f in files) {
      final bytes = await f.xFile.readAsBytes();
      // The picker's plain copy in the cache is not needed once read.
      await deleteQuietly(f.path);
      if (f.name.toLowerCase().endsWith('.pdf')) {
        await _addPdf(bytes);
      } else {
        _pages.add(bytes);
      }
    }
    if (mounted) setState(() {});
  }

  /// A PDF the lab sent: each page becomes an image, then goes through the
  /// same clean-and-encrypt path as a photo. At most 12 pages.
  Future<void> _addPdf(Uint8List bytes) async {
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

  // ---- reading -------------------------------------------------------------

  Future<void> _read() async {
    final s = AppScope.of(context);
    final scanner = s.scanner;
    setState(() {
      _step = _Step.reading;
      _progress = 'Reading page 1 of ${_pages.length}…';
    });
    var draft = CaptureDraft.empty;
    _readFailed = false;
    if (scanner != null) {
      try {
        draft = await scanner.extract(_pages, today: s.clock(), progress: (done, total) {
          if (mounted && done < total) setState(() => _progress = 'Reading page ${done + 1} of $total…');
        });
      } on Object {
        _readFailed = true;
      }
    }
    if (!mounted) return;
    _fill(draft);
    setState(() => _step = _Step.review);
  }

  void _fill(CaptureDraft d) {
    _draft = d;
    if (d.kind.value case final k? when d.readAnything) {
      _kind = k;
      _kindCheck = _Check(d.kind);
    }
    _title.text = d.title.value ?? '';
    _titleCheck = _Check(d.title);
    _place.text = d.place.value ?? '';
    _placeCheck = _Check(d.place);
    _doctor.text = d.doctor.value ?? '';
    _doctorCheck = _Check(d.doctor);
    _date = d.date.value;
    _dateCheck = _Check(d.date);
    _values
      ..clear()
      ..addAll(d.results.map(_Value.new));
    _medicines
      ..clear()
      ..addAll(d.medicines.map(_Medicine.new));
  }

  List<_Check> get _checks => [
        _kindCheck,
        if (_kind != RecordKind.prescription) _titleCheck,
        _placeCheck,
        _doctorCheck,
        _dateCheck,
        if (_kind == RecordKind.report) ..._values.map((v) => v.check),
        if (_kind == RecordKind.prescription) ..._medicines.map((m) => m.check),
      ];

  int get _waiting => _checks.where((c) => !c.ok).length;

  // ---- saving --------------------------------------------------------------

  String? _problem() {
    if (_kind == RecordKind.prescription) {
      if (_medicines.every((m) => m.name.text.trim().isEmpty)) return 'Add at least one medicine, as written.';
    } else if (_title.text.trim().isEmpty) {
      return 'Say what this is, e.g. Lipid panel.';
    }
    if (_date == null) return 'Pick the date printed on it.';
    for (final v in _values) {
      if (_kind != RecordKind.report) break;
      final n = double.tryParse(v.value.text.trim());
      if (v.analyte == null && v.value.text.trim().isEmpty) continue; // an empty row
      if (v.analyte == null || n == null || v.unit.text.trim().isEmpty) return 'Each value needs a test, a number and a unit — exactly as printed. Remove a row you do not want.';
    }
    return null;
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final rng = Random.secure();
    String id() => 'r-${List.generate(8, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final date = _date!;
    final drafts = <HealthRecord>[];
    if (_kind == RecordKind.prescription) {
      for (final m in _medicines.where((m) => m.name.text.trim().isNotEmpty)) {
        final days = int.tryParse(m.days.text.trim());
        drafts.add(HealthRecord(
          id: id(),
          patientId: s.currentPatientId!,
          kind: RecordKind.prescription,
          title: m.name.text.trim(),
          date: date,
          source: RecordSource.smartCapture,
          originalFormat: _fromPdf ? 'pdf' : null,
          doctor: text(_doctor),
          facility: text(_place),
          dose: Dose(morning: m.dose[0], afternoon: m.dose[1], night: m.dose[2]),
          timing: m.timing,
          endDate: days == null || days <= 0 ? null : date.add(Duration(days: days)),
        ));
      }
    } else {
      final results = <LabResult>[
        if (_kind == RecordKind.report)
          for (final v in _values)
            if (v.analyte != null && double.tryParse(v.value.text.trim()) != null)
              LabResult(
                analyte: v.analyte!,
                value: double.parse(v.value.text.trim()),
                unit: v.unit.text.trim(),
                printedLow: double.tryParse(v.low.text.trim()),
                printedHigh: double.tryParse(v.high.text.trim()),
              ),
      ];
      drafts.add(HealthRecord(
        id: id(),
        patientId: s.currentPatientId!,
        kind: _kind,
        title: _title.text.trim(),
        date: date,
        sampleDate: _kind == RecordKind.report ? date : null,
        source: RecordSource.smartCapture,
        originalFormat: _fromPdf ? 'pdf' : null,
        labName: _kind == RecordKind.prescription ? null : text(_place),
        facility: text(_place),
        doctor: text(_doctor),
        results: results,
      ));
    }
    setState(() => _saving = true);
    try {
      await s.addScannedAll(drafts: drafts, rawPages: _pages, checked: _how());
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// For the access log: what the scan read and what the patient changed.
  String _how() {
    if (!_draft.readAnything) return 'from a scan, typed in by the patient';
    final all = _checks.where((c) => c.needed || c.edited).toList();
    final changed = all.where((c) => c.edited).length;
    return 'from a scan, checked by the patient against the photo ($changed of ${all.length} highlighted or edited items changed)';
  }

  // ---- screens ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: switch (_step) {
          _Step.capture => _capture(),
          _Step.reading => _reading(),
          _Step.review => _review(),
        },
      );

  String get _whose {
    final s = AppScope.of(context);
    return s.familyOnPhone().length > 1 ? ' Saving to ${s.currentPatient!.name}\'s records.' : '';
  }

  Widget _capture() => ListView(children: [
        Masthead(
          eyebrow: 'Add a report or prescription',
          title: 'Add every page',
          description: 'LifeTrack reads it on this phone, then you check what it read. The photo is kept for your doctor, encrypted, with location details removed.$_whose',
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
          child: SlabButton(_converting ? 'Opening the PDF…' : 'From files — PDF or photo', icon: LucideIcons.fileText, variant: ButtonVariant.outline, onPressed: _converting ? null : _file),
        ),
        if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        SizedBox(height: 16),
        if (_pages.isEmpty)
          Note('Tip: lay the page flat in good light and fill the frame, one photo per page. You can also share a report to LifeTrack straight from WhatsApp or your email.', icon: LucideIcons.lightbulb)
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
                    Positioned(left: 6, bottom: 6, child: Badge2('Page ${i + 1}')),
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
            _pages.isEmpty ? 'Add at least one page' : 'Read ${_pages.length} page${_pages.length == 1 ? '' : 's'}',
            icon: _pages.isEmpty ? null : LucideIcons.scanText,
            onPressed: _pages.isEmpty || _converting ? null : _read,
          ),
        ),
      ]);

  Widget _reading() => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(_progress, style: LT.label),
            SizedBox(height: 8),
            Text('Read on this phone. The pages are not sent anywhere to be read.', textAlign: TextAlign.center, style: LT.small),
          ]),
        ),
      );

  void _openPage(int i) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PageViewer(pages: _pages, initial: i)));

  Widget _review() {
    final waiting = _waiting;
    final read = _draft.readAnything;
    return ListView(children: [
      Masthead(
        eyebrow: 'Check it against the photo',
        title: read ? 'Is this what it says?' : 'What is it?',
        description: read
            ? 'Tap a page to zoom. Fix anything that is wrong. Highlighted items are ones LifeTrack was not sure of — tick each one or correct it.'
            : _readFailed || AppScope.of(context).scanner != null
                ? 'LifeTrack could not read this page. Type in what is printed — you can skip the values, the photo carries them.'
                : 'Type in what is printed — you can skip the values, the photo carries them.',
      ),
      SizedBox(
        height: 120,
        child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.fromLTRB(16, 12, 16, 0), children: [
          for (final (i, p) in _pages.indexed)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                label: 'Open page ${i + 1}',
                child: GestureDetector(
                  onTap: () => _openPage(i),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(p, width: 80, fit: BoxFit.cover, cacheWidth: 240)),
                ),
              ),
            ),
        ]),
      ),
      if (_draft.handwriting)
        Padding(
          padding: EdgeInsets.only(top: 14),
          child: CautionPanel(
            title: 'This looks handwritten',
            child: Text('LifeTrack reads print well and handwriting poorly. Check every highlighted item, and type in anything it missed.', style: LT.small.copyWith(color: LT.cautionInk)),
          ),
        ),
      SizedBox(height: 10),
      _checked(
        _kindCheck,
        Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in [RecordKind.report, RecordKind.prescription, RecordKind.scan])
              Chip2(kindLabel(k), selected: _kind == k, onTap: () => setState(() {
                    _kind = k;
                    _kindCheck.edited = _kindCheck.done = true;
                  })),
          ]),
        ),
      ),
      if (_kind != RecordKind.prescription) ...[
        _checked(_titleCheck, LabeledField(label: _kind == RecordKind.scan ? 'What was scanned' : 'Report name', child: TextField(controller: _title, onChanged: (_) => _edited(_titleCheck)))),
        if (_kind == RecordKind.report)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _commonReports)
                Chip2(c, selected: _title.text == c, onTap: () => setState(() {
                      _title.text = c;
                      _edited(_titleCheck);
                    })),
            ]),
          ),
      ],
      _checked(
        _placeCheck,
        LabeledField(
          label: _kind == RecordKind.prescription ? 'Clinic or hospital' : 'Lab name, as printed',
          child: TextField(controller: _place, onChanged: (_) => _edited(_placeCheck), decoration: InputDecoration(hintText: 'e.g. Thyrocare, Dr Lal PathLabs')),
        ),
      ),
      _checked(_doctorCheck, LabeledField(label: _kind == RecordKind.report ? 'Referred by (doctor)' : 'Doctor', child: TextField(controller: _doctor, onChanged: (_) => _edited(_doctorCheck)))),
      _checked(
        _dateCheck,
        LabeledField(
          label: _kind == RecordKind.report ? 'Date the sample was taken' : 'Date on the document',
          hint: 'This is what tells a doctor how recent it is.',
          child: FieldButton(
            text: _date == null ? 'Pick the date printed on it' : fullDate(_date!),
            placeholder: _date == null,
            onTap: () async {
              final now = AppScope.of(context).clock();
              final d = await showDatePicker(context: context, initialDate: _date ?? now, firstDate: DateTime(1990), lastDate: now);
              if (d != null) {
                setState(() {
                  _date = d;
                  _edited(_dateCheck);
                });
              }
            },
          ),
        ),
      ),
      if (_kind == RecordKind.report) ..._valuesSection(),
      if (_kind == RecordKind.prescription) ..._medicinesSection(),
      if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: SlabButton(
          _saving
              ? 'Saving…'
              : waiting > 0
                  ? 'Check $waiting highlighted item${waiting == 1 ? '' : 's'} first'
                  : read
                      ? 'This matches my ${_kind == RecordKind.prescription ? 'prescription' : 'report'}'
                      : 'Save',
          icon: waiting > 0 ? null : LucideIcons.check,
          onPressed: _saving || waiting > 0 ? null : _save,
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Text(
          read ? 'By saving you confirm these details match the photo. The photo is saved with them, so a doctor can always check.' : 'The photo is saved with these details, so a doctor can always check.',
          textAlign: TextAlign.center,
          style: LT.small,
        ),
      ),
    ]);
  }

  void _edited(_Check c) => setState(() => c
    ..edited = true
    ..done = true);

  /// Wraps a field the scan was unsure of: highlighted, with what was read
  /// and a tick. Fields the scan was sure of (or the patient typed) pass through.
  Widget _checked(_Check c, Widget field) {
    if (!c.needed) return field;
    return Container(
      margin: EdgeInsets.fromLTRB(10, 0, 10, 12),
      padding: EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LT.radiusLg),
        border: Border.all(color: c.done ? LT.rule : LT.cautionBorder, width: c.done ? 1 : 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Row(children: [
            Badge2(c.done ? 'Checked' : 'Check this', tone: c.done ? BadgeTone.outline : BadgeTone.caution),
            if (c.seen != null) ...[
              SizedBox(width: 8),
              Expanded(child: Text('Read as “${c.seen}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: LT.small.copyWith(fontSize: 11.5))),
            ],
          ]),
        ),
        field,
        _tick(c),
      ]),
    );
  }

  Widget _tick(_Check c) => CheckboxListTile(
        value: c.done,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('Matches the photo', style: LT.label.copyWith(fontSize: 14)),
        onChanged: (v) => setState(() => c.done = v ?? false),
      );

  List<Widget> _valuesSection() => [
        Eyebrow(_values.isEmpty ? 'Key values (optional)' : 'Values read from the report'),
        for (final (i, v) in _values.indexed)
          _wrapRow(
            v.check,
            ShadCard(
              margin: v.check.needed ? EdgeInsets.fromLTRB(6, 0, 6, 4) : EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: v.analyte,
                      isExpanded: true,
                      hint: Text('Which test'),
                      items: [for (final e in analyteNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (x) => setState(() {
                        v.analyte = x;
                        _edited(v.check);
                      }),
                    ),
                  ),
                  IconButton(tooltip: 'Remove this value', icon: Icon(LucideIcons.trash2, size: 18), onPressed: () => setState(() => _values.removeAt(i))),
                ]),
                SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: v.value, onChanged: (_) => _edited(v.check), keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Result'))),
                  SizedBox(width: 8),
                  Expanded(child: TextField(controller: v.unit, onChanged: (_) => _edited(v.check), decoration: InputDecoration(hintText: 'Unit'))),
                ]),
                SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: v.low, onChanged: (_) => _edited(v.check), keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Lab range from'))),
                  SizedBox(width: 8),
                  Expanded(child: TextField(controller: v.high, onChanged: (_) => _edited(v.check), keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'to'))),
                ]),
              ]),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Add a value', variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => setState(() => _values.add(_Value()))),
        ),
      ];

  List<Widget> _medicinesSection() => [
        Eyebrow(_medicines.isEmpty ? 'Medicines' : 'Medicines read from the prescription'),
        for (final (i, m) in _medicines.indexed)
          _wrapRow(
            m.check,
            ShadCard(
              margin: m.check.needed ? EdgeInsets.fromLTRB(6, 0, 6, 4) : EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: TextField(controller: m.name, onChanged: (_) => _edited(m.check), decoration: InputDecoration(hintText: 'Medicine and strength, e.g. Metformin 500 mg'))),
                  IconButton(tooltip: 'Remove this medicine', icon: Icon(LucideIcons.trash2, size: 18), onPressed: () => setState(() => _medicines.removeAt(i))),
                ]),
                SizedBox(height: 10),
                Row(children: [
                  for (final (j, slot) in ['Morning', 'Afternoon', 'Night'].indexed) ...[
                    if (j > 0) SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: m.dose[j],
                        isExpanded: true,
                        decoration: InputDecoration(labelText: slot),
                        items: [for (var n = 0; n <= 3; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                        onChanged: (n) => setState(() {
                          m.dose[j] = n ?? 0;
                          _edited(m.check);
                        }),
                      ),
                    ),
                  ],
                ]),
                SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (key, label) in [('before_food', 'Before food'), ('after_food', 'After food'), ('with_food', 'With food')])
                    Chip2(label, selected: m.timing == key, onTap: () => setState(() {
                          m.timing = m.timing == key ? null : key;
                          _edited(m.check);
                        })),
                ]),
                SizedBox(height: 10),
                TextField(
                  controller: m.days,
                  onChanged: (_) => _edited(m.check),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: 'For how many days? Blank if ongoing'),
                ),
              ]),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Add a medicine', variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => setState(() => _medicines.add(_Medicine()))),
        ),
      ];

  Widget _wrapRow(_Check c, Widget card) => c.needed ? _checked(c, card) : card;
}

/// Full-screen pages, pinch to zoom, for checking the small print.
class _PageViewer extends StatelessWidget {
  const _PageViewer({required this.pages, required this.initial});
  final List<Uint8List> pages;
  final int initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView(
          controller: PageController(initialPage: initial),
          children: [
            for (final p in pages) InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(p))),
          ],
        ),
      );
}
