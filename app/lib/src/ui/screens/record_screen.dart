import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/insight.dart';
import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../../model/health_record.dart';
import '../app_scope.dart';
import 'add_record_screen.dart';
import '../theme.dart';
import '../widgets/insight_card.dart';
import '../widgets/parts.dart';
import '../widgets/prescription_card.dart';
import 'originals_viewer.dart';
import 'records_screen.dart' show iconForKind, kindLabel;

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
      appBar: AppBar(actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(LucideIcons.ellipsisVertical),
          onSelected: (v) async {
            if (v == 'edit') {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddRecordScreen(editing: r)));
              if (context.mounted) AppScope.changed(context);
            } else if (v == 'delete') {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Delete "${r.title}"?'),
                  content: Text(r.attachmentId == null
                      ? 'It is removed from this phone and, at the next backup, from your backup. Anything already shared with a doctor is not recalled by this.'
                      : 'It and its original pages are removed from this phone and, at the next backup, from your backup. Anything already shared with a doctor is not recalled by this.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep')),
                    TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                  ],
                ),
              );
              if (yes != true || !context.mounted) return;
              await s.deleteRecord(r);
              if (!context.mounted) return;
              AppScope.changed(context);
              Navigator.of(context).pop();
            }
          },
          itemBuilder: (_) => [
            if (r.editable) const PopupMenuItem(value: 'edit', child: Text('Edit'))
            else const PopupMenuItem(enabled: false, value: 'signed', child: Text('Signed — can\'t be edited')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(iconForKind(r.kind)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title, style: LT.title),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Badge2(kindLabel(r.kind)),
                          Badge2(fullDate(r.date), tone: BadgeTone.outline),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (r.attachmentId != null) OriginalsStrip(record: r),
          if (r.kind == RecordKind.prescription)
            PrescriptionCard(record: r, now: s.clock())
          else
            ShadCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (r.doctor != null) _meta(LucideIcons.stethoscope, 'Doctor', r.doctor!),
                  if (r.facility != null) _meta(LucideIcons.hospital, 'Clinic or hospital', r.facility!),
                  if (r.dose != null) _meta(LucideIcons.pill, 'Dose (morning–afternoon–night)', r.dose!.display),
                  _meta(LucideIcons.fileCheck, 'Source', switch (r.source) {
                    RecordSource.typedByPatient => 'Typed in by you, no original attached',
                    RecordSource.smartCapture => 'Photo of the original, values confirmed by you',
                    RecordSource.doctorIssued => 'Signed by a verified doctor',
                    RecordSource.labSigned => 'Delivered by the lab',
                    RecordSource.restoredFromBackup => 'Restored from your backup',
                  }, last: true),
                ],
              ),
            ),
          if (r.results.isNotEmpty) ...[
            const Eyebrow('Values as reported'),
            ShadCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, res) in r.results.indexed)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        border: i == r.results.length - 1 ? null : const Border(bottom: BorderSide(color: LT.rule)),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(analyteName(res.analyte), style: LT.label.copyWith(fontSize: 14.5))),
                          Text('${_fmt(res.value)} ${res.unit}', style: LT.data),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_run == null && s.insightsEnabled() == false)
              const Note(
                'Turn on Insights to have these values compared with published reference ranges.',
                icon: LucideIcons.activity,
                margin: EdgeInsets.fromLTRB(16, 4, 16, 0),
              )
            else ...[
              if (cited.isNotEmpty || unchecked.isNotEmpty) const Eyebrow('From Insights'),
              for (final i in cited) InsightCard(insight: i),
              for (final u in unchecked)
                CautionPanel(
                  title: '${analyteName(u.analyte)} was not checked',
                  child: Text(u.explanation, style: LT.small.copyWith(color: LT.cautionInk)),
                ),
            ],
          ],
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label, String value, {bool last = false}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: LT.rule)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: LT.ink3),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: LT.small)),
        Flexible(
          child: Text(value, style: LT.label.copyWith(fontSize: 14), textAlign: TextAlign.right),
        ),
      ],
    ),
  );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
