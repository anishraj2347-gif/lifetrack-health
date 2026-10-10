import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// Starts at 0-0-0 so nobody gets reminders for a dose they never chose.
  final _dose = [0, 0, 0];

  /// "Only when needed" (SOS): saved with no dose, so no reminders.
  bool _asNeeded = false;
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
    if (r.kind == RecordKind.prescription && r.dose == null) _asNeeded = true;
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
    if (_kind == RecordKind.prescription && !_asNeeded && _dose.every((n) => n == 0)) {
      setState(() => _error = 'Set how many to take in the morning, afternoon or night — or choose "Only when needed".');
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
      dose: _kind == RecordKind.prescription && !_asNeeded ? Dose(morning: _dose[0], afternoon: _dose[1], night: _dose[2]) : null,
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
              hint: 'How many to take at each time of day.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Opacity(
                  opacity: _asNeeded ? 0.45 : 1,
                  child: IgnorePointer(
                    ignoring: _asNeeded,
                    child: Row(children: [
                      for (final (i, name, icon) in [(0, 'Morning', LucideIcons.sunrise), (1, 'Afternoon', LucideIcons.sun), (2, 'Night', LucideIcons.moon)]) ...[
                        Expanded(child: _DoseStepper(name: name, icon: icon, value: _dose[i], onChanged: (v) => setState(() => _dose[i] = v))),
                        if (i < 2) const SizedBox(width: 8),
                      ],
                    ]),
                  ),
                ),
                SizedBox(height: 10),
                Chip2('Only when needed · no reminders', selected: _asNeeded, onTap: () => setState(() => _asNeeded = !_asNeeded)),
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

/// One time of day: its name, then − count +. Big targets, read out as
/// "Morning dose, 1 tablet".
class _DoseStepper extends StatelessWidget {
  const _DoseStepper({required this.name, required this.icon, required this.value, required this.onChanged});
  final String name;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
        decoration: BoxDecoration(border: Border.all(color: value > 0 ? LT.ink : LT.rule, width: value > 0 ? 1.5 : 1), borderRadius: BorderRadius.circular(LT.radius)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: LT.ink2),
            SizedBox(width: 4),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LT.meta.copyWith(color: LT.ink2))),
          ]),
          Semantics(
            label: '$name dose',
            value: '$value tablet${value == 1 ? '' : 's'}',
            increasedValue: '${value + 1}',
            decreasedValue: '${value > 0 ? value - 1 : 0}',
            onIncrease: value < 9 ? () => onChanged(value + 1) : null,
            onDecrease: value > 0 ? () => onChanged(value - 1) : null,
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _btn(LucideIcons.minus, value > 0 ? () => onChanged(value - 1) : null),
              Text('$value', style: LT.data.copyWith(fontSize: 20)),
              _btn(LucideIcons.plus, value < 9 ? () => onChanged(value + 1) : null),
            ]),
          ),
        ]),
      );

  Widget _btn(IconData i, VoidCallback? onTap) => SizedBox(
        width: 40,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          icon: Icon(i, size: 18),
          color: LT.ink,
          disabledColor: LT.inactive,
        ),
      );
}
