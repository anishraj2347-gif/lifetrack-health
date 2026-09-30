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
};

/// The patient's shared Summary, in the order a doctor reads it in an OPD.
/// Values and their source and age are reproduced; nothing is judged.
class SummaryPanel extends StatelessWidget {
  const SummaryPanel({super.key, required this.bundle});
  final Map<String, Object?> bundle;

  static String age(int d) => d < 14 ? '$d days ago' : d < 60 ? '${(d / 7).round()} weeks ago' : d < 730 ? '${(d / 30.4).round()} months ago' : '${(d / 365).round()} years ago';

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    final withheld = (b['withheld'] as List?) ?? const [];
    final meds = (b['medicines'] as Map?) ?? const {};
    final family = (b['familyIllnesses'] as Map?)?['items'] as List?;
    final docs = b['documents'] as List?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (withheld.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: DT.caution, borderRadius: BorderRadius.circular(14)),
          child: Text('Patient shared selected items. Not shared: ${withheld.join(', ')}.', style: const TextStyle(color: DT.cautionInk)),
        ),
      for (final a in (b['allergies'] as List?) ?? const [])
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: DT.signal, borderRadius: BorderRadius.circular(14)),
          child: Text('Allergy: ${(a as Map)['substance']}${a['reaction'] == null ? '' : ' — ${a['reaction']}'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      _card('Medicines', [
        for (final m in (meds['active'] as List?) ?? const [])
          _row('${(m as Map)['title']}${m['dose'] == null ? '' : ' · ${m['dose']}'}',
              '${m['patientConfirmedAt'] != null ? 'Active · patient confirmed still taking' : 'Active · not confirmed by patient'}${m['prescriber'] == null ? '' : ' · ${m['prescriber']}'}'),
        for (final m in (meds['endedRecently'] as List?) ?? const [])
          _row('${(m as Map)['title']}', 'Course ended ${(m['endsOn'] as String?)?.substring(0, 10) ?? ''}', quiet: true),
      ]),
      _card('Conditions', [for (final c in (b['conditions'] as List?) ?? const []) _row('${(c as Map)['name']}', c['since'] == null ? '' : 'since ${c['since']}')]),
      _card('Latest tests', [
        for (final t in (b['latestTests'] as List?) ?? const [])
          () {
            final m = t as Map;
            final r = m['printedRange'] as Map?;
            final prev = m['previous'] as Map?;
            final src = switch (m['source']) { 'signed' => 'Lab / doctor signed', 'photoOfReport' => 'Photo of report', _ => 'Patient-typed, no source' };
            return _row(
              '${_names[m['analyte']] ?? m['analyte']}  ${m['value']} ${m['unit']}',
              [
                age(m['ageDays'] as int),
                if (m['lab'] != null) m['lab'],
                if (r != null) 'lab range ${r['low'] ?? ''}${r['low'] != null && r['high'] != null ? '–' : ''}${r['high'] ?? ''}',
                if (prev != null) 'previous ${prev['value']} (${(prev['sampledOn'] as String).substring(0, 7)})',
                src,
              ].join(' · '),
              quiet: m['source'] == 'patientTyped',
            );
          }(),
      ]),
      if (family != null)
        _card('Family illnesses · patient-reported', [for (final f in family) _row('${(f as Map)['relation']}: ${f['condition']}', f['onset'] == null ? '' : 'at ${f['onset']}')]),
      if (docs != null) _card('All shared documents', [for (final d in docs) _row('${(d as Map)['title']}', '${(d['date'] as String).substring(0, 10)} · ${d['kind']}${d['lab'] == null ? '' : ' · ${d['lab']}'}')]),
    ]);
  }

  Widget _card(String title, List<Widget> rows) => rows.isEmpty
      ? const SizedBox.shrink()
      : Card0(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: DT.muted), const SizedBox(height: 4), ...rows]));

  Widget _row(String main, String sub, {bool quiet = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(main, style: DT.h2.copyWith(fontSize: 15, color: quiet ? DT.ink3 : DT.ink)),
          if (sub.isNotEmpty) Text(sub, style: DT.muted.copyWith(fontSize: 12.5)),
        ]),
      );
}
