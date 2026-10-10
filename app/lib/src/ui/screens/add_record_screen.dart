import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteNames;
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'records_screen.dart' show kindLabel;
import 'scan_report_screen.dart';

class AddRecordScreen extends StatefulWidget {
  const AddRecordScreen({super.key, this.editing});

  /// When set, the form corrects this record instead of adding one.
  final HealthRecord? editing;
  @override
  State<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _ResultRow {
  String? analyte;
  final value = TextEditingController();
  final unit = TextEditingController();
}

class _AddRecordScreenState extends State<AddRecordScreen> {
  RecordKind _kind = RecordKind.prescription;
  final _title = TextEditingController();
  final _doctor = TextEditingController();
  final _facility = TextEditingController();
  final _ingredient = TextEditingController();
  DateTime _date = DateTime.now();
  final _dose = [1, 0, 1];
  final _results = <_ResultRow>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    if (r == null) return;
    _kind = r.kind;
    _title.text = r.title;
    _doctor.text = r.doctor ?? '';
    _facility.text = r.facility ?? '';
    _ingredient.text = r.ingredient ?? '';
    _date = r.date;
    if (r.dose case final d?) {
      _dose
        ..[0] = d.morning
        ..[1] = d.afternoon
        ..[2] = d.night;
    }
    for (final x in r.results) {
      final row = _ResultRow()..analyte = x.analyte;
      row.value.text = x.value == x.value.roundToDouble() ? x.value.toStringAsFixed(0) : '${x.value}';
      row.unit.text = x.unit;
      _results.add(row);
    }
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Say what the document is.');
      return;
    }
    final results = <LabResult>[];
    for (final row in _results) {
      final v = double.tryParse(row.value.text.trim());
      if (row.analyte == null || v == null || row.unit.text.trim().isEmpty) {
        setState(() => _error = 'Each value needs a test, a number and a unit — exactly as printed.');
        return;
      }
      results.add(LabResult(analyte: row.analyte!, value: v, unit: row.unit.text.trim()));
    }
    final rng = Random.secure();
    final old = widget.editing;
    final record = HealthRecord(
      id: old?.id ?? 'r-${List.generate(8, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
      patientId: old?.patientId ?? s.currentPatientId!,
      kind: _kind,
      title: _title.text.trim(),
      date: _date,
      source: old?.source ?? RecordSource.typedByPatient,
      attachmentId: old?.attachmentId,
      labName: old?.labName,
      sampleDate: old?.sampleDate,
      endDate: old?.endDate,
      patientConfirmedAt: old?.patientConfirmedAt,
      instructions: old?.instructions,
      timing: old?.timing,
      prescriberRegistration: old?.prescriberRegistration,
      doctor: _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
      facility: _facility.text.trim().isEmpty ? null : _facility.text.trim(),
      dose: _kind == RecordKind.prescription ? Dose(morning: _dose[0], afternoon: _dose[1], night: _dose[2]) : null,
      ingredient: _kind == RecordKind.prescription && _ingredient.text.trim().isNotEmpty ? _ingredient.text.trim().toLowerCase() : null,
      results: _kind == RecordKind.report ? results : [],
    );
    if (old == null) {
      await s.addRecord(record);
    } else {
      await s.updateRecord(record);
    }
    if (!mounted) return;
    celebrate(context, old == null ? 'Record saved' : 'Changes saved');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(children: [
          Masthead(eyebrow: widget.editing == null ? 'Add record' : 'Edit record', title: widget.editing == null ? 'Type it in' : 'Correct it'),
          if (widget.editing == null) ShadCard(
            margin: EdgeInsets.fromLTRB(16, 16, 16, 4),
            color: LT.primary,
            onTap: () async {
              final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ScanReportScreen()));
              if (saved == true && context.mounted) Navigator.of(context).pop();
            },
            child: Row(children: [
              IconTile(LucideIcons.camera, color: LT.onAccent, background: LT.accent),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Photograph a paper report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
                  SizedBox(height: 4),
                  Text('Best for lab reports and prescriptions on paper', style: TextStyle(fontSize: 12.5, color: LT.onDarkMuted)),
                ]),
              ),
              Icon(LucideIcons.chevronRight, color: LT.onDarkMuted),
            ]),
          ),
          if (widget.editing == null) Eyebrow('Or type it in'),
          Note('Copy values exactly as printed, including the unit. LifeTrack compares only what matches its ranges; anything else is shown as not checked.', icon: LucideIcons.info),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in RecordKind.values)
                Chip2(kindLabel(k), selected: _kind == k, onTap: widget.editing != null ? null : () => setState(() => _kind = k)),
            ]),
          ),
          LabeledField(label: 'What is it', child: TextField(controller: _title, decoration: InputDecoration(hintText: 'e.g. Metformin 500 mg'))),
          LabeledField(
            label: 'Date on the document',
            child: FieldButton(
              text: fullDate(_date),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1950), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          if (_kind != RecordKind.note) ...[
            LabeledField(label: 'Doctor', child: TextField(controller: _doctor)),
            LabeledField(label: 'Clinic or hospital', child: TextField(controller: _facility)),
          ],
          if (_kind == RecordKind.prescription) ...[
            LabeledField(
              label: 'Active ingredient',
              hint: 'e.g. metformin. Used to spot two prescriptions for the same medicine under different brand names.',
              child: TextField(controller: _ingredient),
            ),
            LabeledField(
              label: 'Dose',
              hint: 'Morning · afternoon · night. Tap a box to change it.',
              child: Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _dose[i] = (_dose[i] + 1) % 4),
                      borderRadius: BorderRadius.circular(LT.radius),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: LT.rule), borderRadius: BorderRadius.circular(LT.radius)),
                        child: Text('${_dose[i]}', style: LT.data.copyWith(fontSize: 18)),
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 8),
                ],
              ]),
            ),
          ],
          if (_kind == RecordKind.report) ...[
            Eyebrow('Values'),
            for (final row in _results)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      initialValue: row.analyte,
                      isExpanded: true,
                      hint: Text('Test'),
                      items: [for (final e in analyteNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => row.analyte = v),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(flex: 3, child: TextField(controller: row.value, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(hintText: 'Value'))),
                  SizedBox(width: 8),
                  Expanded(flex: 3, child: TextField(controller: row.unit, decoration: InputDecoration(hintText: 'Unit'))),
                ]),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SlabButton('Add a value', variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => setState(() => _results.add(_ResultRow()))),
            ),
          ],
          if (_kind == RecordKind.note) Note('Personal notes stay on this phone. They are never included in a backup unless you turn that on.', icon: LucideIcons.smartphone),
          if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
          Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 28), child: SlabButton('Save record', icon: LucideIcons.check, onPressed: _save)),
        ]),
      );
}
