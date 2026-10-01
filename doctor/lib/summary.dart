import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';

const _names = {
  'glucose_fasting': 'Fasting glucose',
  'hba1c': 'HbA1c',
  'total_cholesterol': 'Total cholesterol',
  'ldl': 'LDL cholesterol',
  'hdl': 'HDL cholesterol',
  'triglycerides': 'Triglycerides',
  'haemoglobin': 'Haemoglobin',
  'creatinine': 'Creatinine',
  'tsh': 'TSH',
  'ferritin': 'Ferritin',
  'vitamin_d': 'Vitamin D',
};

/// The patient's shared Summary, in the order a doctor reads it in an OPD.
/// Values and their source and age are reproduced; nothing is judged.
/// Where the patient photographed the paper report, the original is one
/// click away — that is what lets a doctor trust it instead of repeating it.
class SummaryPanel extends StatelessWidget {
  const SummaryPanel({super.key, required this.bundle});
  final Map<String, Object?> bundle;

  static String fmt(Object? v) {
    final d = (v! as num).toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d';
  }

  static String range(Map r) {
    final lo = r['low'], hi = r['high'];
    if (lo != null && hi != null) return '${fmt(lo)}–${fmt(hi)}';
    if (hi != null) return '${fmt(hi)} or below';
    return '${fmt(lo)} or above';
  }

  static String age(int d) => d <= 0
      ? 'today'
      : d == 1
      ? 'yesterday'
      : d < 14
      ? '$d days ago'
      : d < 60
      ? '${(d / 7).round()} weeks ago'
      : d < 730
      ? '${(d / 30.4).round()} months ago'
      : '${(d / 365).round()} years ago';

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    final withheld = (b['withheld'] as List?) ?? [];
    final meds = (b['medicines'] as Map?) ?? {};
    final family = (b['familyIllnesses'] as Map?)?['items'] as List?;
    final home = (b['homeReadings'] as Map?)?['items'] as List?;
    final docs = b['documents'] as List?;
    final originals = ((b['originals'] as Map?) ?? {})
        .cast<String, Object?>();
    final omitted = (b['originalsOmitted'] as int?) ?? 0;

    Widget? view(String id, String title) => originals[id] == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showOriginals(context, title, [
                for (final p in originals[id]! as List)
                  base64Decode(p as String),
              ]),
              icon: Icon(Icons.description_outlined, size: 18),
              label: Text(
                'View original report · ${(originals[id]! as List).length} page${(originals[id]! as List).length == 1 ? '' : 's'}',
              ),
            ),
          );

    final nothing =
        ((b['allergies'] as List?) ?? []).isEmpty &&
        ((b['conditions'] as List?) ?? []).isEmpty &&
        (((meds['active'] as List?) ?? []).isEmpty) &&
        (((meds['endedRecently'] as List?) ?? []).isEmpty) &&
        ((b['latestTests'] as List?) ?? []).isEmpty &&
        (family == null || family.isEmpty) &&
        (home == null || home.isEmpty) &&
        (docs == null || docs.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nothing)
          Card0(
            child: Text(
              'No records in what was shared. The patient may not have added any yet — ask them, or order what you need.',
              style: DT.body,
            ),
          ),
        if (withheld.isNotEmpty)
          _note(
            'Patient shared selected items. Not shared: ${withheld.join(', ')}.',
          ),
        if (omitted > 0)
          _note(
            '$omitted original report${omitted == 1 ? ' was' : 's were'} too large to send. Ask the patient to show it on their phone.',
          ),
        for (final a in (b['allergies'] as List?) ?? [])
          Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DT.signalFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Allergy: ${(a as Map)['substance']}${a['reaction'] == null ? '' : ' — ${a['reaction']}'}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        _card('Medicines', [
          for (final m in (meds['active'] as List?) ?? [])
            _row(
              '${(m as Map)['title']}${m['dose'] == null ? '' : ' · ${m['dose']}'}',
              '${m['patientConfirmedAt'] != null ? 'Active · patient confirmed still taking' : 'Active · not confirmed by patient'}${m['prescriber'] == null ? '' : ' · ${m['prescriber']}'}',
            ),
          for (final m in (meds['endedRecently'] as List?) ?? [])
            _row(
              '${(m as Map)['title']}',
              'Course ended ${(m['endsOn'] as String?)?.substring(0, 10) ?? ''}',
              quiet: true,
            ),
        ]),
        _card('Conditions', [
          for (final c in (b['conditions'] as List?) ?? [])
            _row(
              '${(c as Map)['name']}',
              c['since'] == null ? '' : 'since ${c['since']}',
            ),
        ]),
        _card('Latest tests', [
          for (final t in (b['latestTests'] as List?) ?? [])
            () {
              final m = t as Map;
              final r = m['printedRange'] as Map?;
              final prev = m['previous'] as Map?;
              final name = '${_names[m['analyte']] ?? m['analyte']}';
              final src = switch (m['source']) {
                'signed' => 'Lab / doctor signed',
                'photoOfReport' =>
                  m['original'] == 'pdf' ? 'PDF of report' : 'Photo of report',
                _ => 'Patient-typed, no source',
              };
              return _row(
                '$name  ${fmt(m['value'])} ${m['unit']}',
                [
                  age(m['ageDays'] as int),
                  if (m['lab'] != null) m['lab'],
                  if (r != null) 'lab range ${range(r)}',
                  if (prev != null)
                    'previous ${fmt(prev['value'])} (${(prev['sampledOn'] as String).substring(0, 7)})',
                  src,
                ].join(' · '),
                quiet: m['source'] == 'patientTyped',
                action: view(m['recordId'] as String, name),
              );
            }(),
        ]),
        if (home != null)
          _card('Home readings · measured by the patient, last 30 days', [
            if (home.isEmpty) _row('None recorded in the last 30 days', '', quiet: true),
            for (final v in home.cast<Map>())
              _row(
                v['kind'] == 'bloodPressure'
                    ? 'BP ${v['sys']}/${v['dia']} mmHg${v['pulse'] == null ? '' : ' · pulse ${v['pulse']}'}'
                    : 'Sugar ${fmt(v['glucose'])} mg/dL${v['context'] == null ? '' : ' · ${{'fasting': 'fasting', 'afterMeal': 'after a meal', 'random': 'random', 'bedtime': 'bedtime'}[v['context']]}'}',
                (v['at'] as String).substring(0, 16).replaceFirst('T', ' '),
              ),
          ]),
        if (family != null)
          _card('Family illnesses · patient-reported', [
            for (final f in family)
              _row(
                '${(f as Map)['relation']}: ${f['condition']}',
                f['onset'] == null ? '' : 'at ${f['onset']}',
              ),
          ]),
        if (docs != null)
          _card('All shared documents', [
            for (final d in docs)
              _row(
                '${(d as Map)['title']}',
                '${(d['date'] as String).substring(0, 10)} · ${d['kind']}${d['lab'] == null ? '' : ' · ${d['lab']}'}',
                action: view(d['id'] as String, d['title'] as String),
              ),
          ]),
      ],
    );
  }

  Widget _note(String text) => Container(
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DT.caution,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text, style: TextStyle(color: DT.cautionInk)),
  );

  Widget _card(String title, List<Widget> rows) => rows.isEmpty
      ? SizedBox.shrink()
      : Card0(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DT.muted),
              SizedBox(height: 4),
              ...rows,
            ],
          ),
        );

  Widget _row(
    String main,
    String sub, {
    bool quiet = false,
    Widget? action,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          main,
          style: DT.h2.copyWith(fontSize: 15, color: quiet ? DT.ink3 : DT.ink),
        ),
        if (sub.isNotEmpty) Text(sub, style: DT.muted.copyWith(fontSize: 12.5)),
        ?action,
      ],
    ),
  );
}

/// The patient's original pages, full size, scroll and zoom. Held in memory
/// with the rest of the share and gone when access ends.
void showOriginals(
  BuildContext context,
  String title,
  List<Uint8List> pages,
) => showDialog<void>(
  context: context,
  builder: (c) => Dialog(
    backgroundColor: DT.hero,
    insetPadding: EdgeInsets.all(24),
    child: SizedBox(
      width: 900,
      height: 1000,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title · original, ${pages.length} page${pages.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: DT.onDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(c).pop(),
                  icon: Icon(Icons.close, color: DT.onDark),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  for (final p in pages)
                    Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Image.memory(p),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
