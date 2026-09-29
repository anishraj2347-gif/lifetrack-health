import 'package:flutter/material.dart';

import '../../ai/insight.dart';
import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/insight_card.dart';
import '../widgets/parts.dart';

/// One record, reproduced as written.
///
/// This screen does **not** judge values. It shows each value and unit and
/// nothing else; any flag comes from Plane A as an [Insight] citing this
/// record, with the output contract (disclaimer, route to a doctor) attached.
/// A second, weaker clinical engine in the view layer is how a 12 mmol/L
/// glucose once rendered as a red hypoglycaemia alarm (audit ruling A).
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.recordId});
  final String recordId;
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  InsightRun? _run;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      AppScope.of(context).runInsights().then((r) {
        if (mounted) setState(() => _run = r);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = s.records().where((x) => x.id == widget.recordId).firstOrNull;
    if (r == null) return const Scaffold(body: Center(child: Text('This record no longer exists.')));
    final cited = _run?.insights.where((i) => i.evidence.contains(r.id)).toList() ?? const <Insight>[];
    final unchecked = _run?.unresolved.where((u) => u.recordId == r.id).toList() ?? const <NotChecked>[];

    return Scaffold(
      appBar: AppBar(backgroundColor: LT.ground, elevation: 0, foregroundColor: LT.ink),
      body: ListView(children: [
        Masthead(eyebrow: r.kind.name, title: r.title),
        _meta('Date on the document', fullDate(r.date)),
        if (r.doctor != null) _meta('Doctor', r.doctor!),
        if (r.facility != null) _meta('Clinic or hospital', r.facility!),
        if (r.dose != null) _meta('Dose · morning–afternoon–night', r.dose!.display),
        _meta('Source', switch (r.source) {
          RecordSource.typedByPatient => 'Typed in by you',
          RecordSource.smartCapture => 'Captured from a photo, confirmed by you',
          RecordSource.doctorIssued => 'Issued by the doctor',
          RecordSource.restoredFromBackup => 'Restored from your backup',
        }),
        if (r.results.isNotEmpty) ...[
          const Eyebrow('Values as reported'),
          for (final res in r.results)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: LT.rule))),
              child: Row(children: [
                Expanded(child: Text(analyteName(res.analyte), style: LT.label)),
                Text('${_fmt(res.value)} ${res.unit}', style: LT.data),
              ]),
            ),
          if (_run == null && s.insightsEnabled() == false)
            const Note('Turn on Insights to have these values compared with published reference ranges.')
          else ...[
            for (final i in cited) InsightCard(insight: i),
            for (final u in unchecked)
              CautionPanel(
                title: '${analyteName(u.analyte)} was not checked',
                child: Text(u.explanation, style: LT.small.copyWith(color: LT.ink)),
              ),
          ],
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _meta(String label, String value) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: LT.eyebrow),
          const SizedBox(height: 5),
          Text(value, style: LT.label),
        ]),
      );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
