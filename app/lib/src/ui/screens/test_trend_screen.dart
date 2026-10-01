import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../../app/test_history.dart';
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import '../widgets/summary_view.dart';
import '../widgets/trend_card.dart';
import 'originals_viewer.dart';
import 'record_screen.dart';

/// Every result of one test, newest first: value, date, age, lab, doctor and
/// source, each one tap from its report and the original. States what was
/// measured and when — never whether a value or a change is good or bad (#8).
class TestTrendScreen extends StatelessWidget {
  const TestTrendScreen({super.key, required this.analyte, required this.unit});
  final String analyte;
  final String unit;

  static String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final records = s.records();
    final series = TrendCard.all(records, min: 1).where((t) => t.analyte == analyte && t.unit == unit).firstOrNull;
    final now = s.clock();
    final rows = [
      for (final r in records)
        for (final x in r.results)
          if (x.analyte == analyte) (r, x),
    ]..sort((a, b) => b.$1.effectiveDate.compareTo(a.$1.effectiveDate));

    Future<void> openRecord(HealthRecord r) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id)));
      if (context.mounted) AppScope.changed(context);
    }

    Future<void> openOriginal(HealthRecord r) async {
      final pages = await s.originals(r);
      if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OriginalsViewer(title: r.title, pages: pages)));
    }

    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(
          eyebrow: 'Results over time',
          title: analyteName(analyte),
          description: rows.isEmpty
              ? null
              : '${rows.length} result${rows.length == 1 ? '' : 's'} · ${fullDate(rows.last.$1.effectiveDate)} – ${fullDate(rows.first.$1.effectiveDate)}',
        ),
        const SizedBox(height: 12),
        if (series != null && series.points.length > 1) TrendCard(series: series, maxColumns: 12),
        const Note(
          'Each value as the lab reported it, with its date and where it came from. Whether a change matters is for your doctor — show them this page.',
          icon: LucideIcons.info,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 4),
        ),
        const Eyebrow('Every result'),
        for (final (i, (r, x)) in rows.indexed)
          ShadCard(
            onTap: () => openRecord(r),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: fmt(x.value), style: LT.title.copyWith(fontSize: 22)),
                    TextSpan(text: '  ${x.unit}', style: LT.small),
                  ])),
                ),
                if (i == 0) const Padding(padding: EdgeInsets.only(right: 6), child: Badge2('Latest', tone: BadgeTone.outline)),
                Badge2(ageOf(now.difference(r.effectiveDate).inDays), tone: BadgeTone.outline),
              ]),
              const SizedBox(height: 6),
              Text(
                [
                  fullDate(r.effectiveDate),
                  ?(r.labName ?? r.facility),
                  if (r.doctor case final d?) d.toLowerCase().startsWith('dr') ? d : 'Dr. $d',
                ].join(' · '),
                style: LT.small,
              ),
              const SizedBox(height: 2),
              Text('${SummaryView.sourceBadge(r.provenance.name, r.originalFormat).$1} · ${r.title}', style: LT.small),
              const SizedBox(height: 6),
              Row(children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => openRecord(r),
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('Open report'),
                ),
                if (r.attachmentId != null) ...[
                  const SizedBox(width: 16),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => openOriginal(r),
                    icon: const Icon(LucideIcons.image, size: 16),
                    label: Text(r.originalFormat == 'pdf' ? 'PDF pages' : 'Original photo'),
                  ),
                ],
              ]),
            ]),
          ),
        const SizedBox(height: 28),
      ]),
    );
  }
}

/// Tiles on Records for the other tests with a trend, under the big card.
class MoreTrends extends StatelessWidget {
  const MoreTrends({super.key, required this.series});
  final List<TrendSeries> series;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final t in series)
          SizedBox(
              width: (MediaQuery.sizeOf(context).width - 32 - 10) / 2,
              child: ShadCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestTrendScreen(analyte: t.analyte, unit: t.unit))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(LucideIcons.chartLine, size: 18, color: LT.ink),
                    const Spacer(),
                    Text('${t.points.length}×', style: LT.small),
                  ]),
                  const SizedBox(height: 8),
                  Text(analyteName(t.analyte), style: LT.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${TestTrendScreen.fmt(t.points.last.$2.value)} ${t.unit} · ${fullDate(t.points.last.$1.effectiveDate)}', style: LT.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
      ]),
    );
  }
}
