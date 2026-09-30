import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../theme.dart';
import 'parts.dart';

/// Renders a share bundle the way a doctor reads it in an OPD: allergies,
/// medicines, conditions, latest tests with source and age, family
/// illnesses. Values are reproduced, never judged.
class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.bundle, this.onOpenOriginal});
  final Map<String, Object?> bundle;

  /// Opens a record's original pages; the test row shows a link when set.
  final void Function(String recordId)? onOpenOriginal;

  static String age(int days) => days < 14
      ? '$days days ago'
      : days < 60
          ? '${(days / 7).round()} weeks ago'
          : days < 730
              ? '${(days / 30.4).round()} months ago'
              : '${(days / 365).round()} years ago';

  static (String, BadgeTone) sourceBadge(String s) => switch (s) {
        'signed' => (t('Lab / doctor signed'), BadgeTone.trace),
        'photoOfReport' => (t('Photo of report'), BadgeTone.neutral),
        _ => (t('Patient-typed'), BadgeTone.outline),
      };

  static String fmt(Object? v) {
    final d = (v! as num).toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d';
  }

  /// "70–100", "5.6 or below", "50 or above" — never a bare number that
  /// reads as either bound.
  static String range(Map r) {
    final lo = r['low'], hi = r['high'];
    if (lo != null && hi != null) return '${fmt(lo)}–${fmt(hi)}';
    if (hi != null) return '${fmt(hi)} or below';
    return '${fmt(lo)} or above';
  }

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    final allergies = (b['allergies'] as List?) ?? const [];
    final conditions = (b['conditions'] as List?) ?? const [];
    final meds = (b['medicines'] as Map?) ?? const {};
    final tests = (b['latestTests'] as List?) ?? const [];
    final family = (b['familyIllnesses'] as Map?)?['items'] as List?;
    final withheld = (b['withheld'] as List?) ?? const [];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (withheld.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: LT.caution, borderRadius: BorderRadius.circular(LT.radius), border: Border.all(color: LT.cautionBorder)),
          child: Text('Patient shared selected items. Not shared: ${withheld.join(', ')}.', style: LT.small.copyWith(color: LT.cautionInk)),
        ),
      for (final a in allergies)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: LT.signal, borderRadius: BorderRadius.circular(LT.radius)),
          child: Text('Allergy: ${(a as Map)['substance']}${a['reaction'] == null ? '' : ' — ${a['reaction']}'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      _block(t('Active medicines'), [
        for (final m in (meds['active'] as List?) ?? const [])
          _line('${(m as Map)['title']}${m['dose'] == null ? '' : ' · ${m['dose']}'}',
              m['patientConfirmedAt'] != null ? t('Patient confirmed still taking') : t('Not confirmed by patient')),
        for (final m in (meds['endedRecently'] as List?) ?? const [])
          _line('${(m as Map)['title']}', 'Course ended ${(m['endsOn'] as String?)?.substring(0, 10) ?? ''}', quiet: true),
      ]),
      _block(t('Conditions'), [
        for (final c in conditions) _line('${(c as Map)['name']}t(', c[')since'] == null ? '' : 'since ${c['since']}'),
      ]),
      _block(t('Latest tests'), [
        for (final test in tests)
          () {
            final m = test as Map;
            final (label, tone) = sourceBadge(m['source'] as String);
            final prev = m['previous'] as Map?;
            final range = m['printedRange'] as Map?;
            final sub = [
              age(m['ageDays'] as int),
              if (m['lab'] != null) m['lab'],
              if (range != null) 'lab range ${SummaryView.range(range)}',
              if (prev != null) 'was ${fmt(prev['value'])} (${(prev['sampledOn'] as String).substring(0, 7)})',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${analyteName(m['analyte'] as String)} ${fmt(m['value'])} ${m['unit']}',
                        style: LT.label.copyWith(fontWeight: FontWeight.w600, color: m['source'] == 'patientTyped' ? LT.ink3 : LT.ink)),
                    Text(sub, style: LT.small.copyWith(fontSize: 12)),
                    if (onOpenOriginal != null && m['hasOriginal'] == true)
                      GestureDetector(
                        onTap: () => onOpenOriginal!(m['recordId'] as String),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(t('View original report'), style: LT.small.copyWith(color: LT.ink, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                        ),
                      ),
                  ]),
                ),
                Badge2(label, tone: tone),
              ]),
            );
          }(),
      ]),
      if (family != null)
        _block(t('Family illnesses · patient-reported'), [
          for (final f in family)
            _line('${(f as Map)['relation']}: ${f['condition']}t(', f[')onset'] == null ? '' : 'at ${f['onset']}'),
        ]),
    ]);
  }

  Widget _block(String title, List<Widget> children) => children.isEmpty
      ? const SizedBox.shrink()
      : ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: LT.small.copyWith(fontWeight: FontWeight.w600, color: LT.ink2)),
            const SizedBox(height: 4),
            ...children,
          ]),
        );

  Widget _line(String main, String sub, {bool quiet = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(main, style: LT.label.copyWith(fontWeight: FontWeight.w600, color: quiet ? LT.ink3 : LT.ink)),
          const SizedBox(height: 4),
          if (sub.isNotEmpty) Text(sub, style: LT.small.copyWith(fontSize: 12)),
        ]),
      );
}
