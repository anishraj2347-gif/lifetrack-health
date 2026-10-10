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
      appBar: GlassAppBar(),
      extendBodyBehindAppBar: true,
      body: ListView(children: [
        Masthead(
          eyebrow: 'Results over time',
          title: analyteName(analyte),
          description: rows.isEmpty
              ? null
              : '${rows.length} result${rows.length == 1 ? '' : 's'} · ${fullDate(rows.last.$1.effectiveDate)} – ${fullDate(rows.first.$1.effectiveDate)}',
        ),
        SizedBox(height: 12),
        if (series != null && series.points.length > 1) TrendCard(series: series, maxColumns: 12),
        Note(
          'Each value as the lab reported it, with its date and where it came from. Whether a change matters is for your doctor — show them this page.',
          icon: LucideIcons.info,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 4),
        ),
        Eyebrow('Every result'),
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
                if (i == 0) Padding(padding: EdgeInsets.only(right: 6), child: Badge2('Latest', tone: BadgeTone.outline)),
                Badge2(ageOf(now.difference(r.effectiveDate).inDays), tone: BadgeTone.outline),
              ]),
              SizedBox(height: 6),
              Text(
                [
                  fullDate(r.effectiveDate),
                  ?(r.labName ?? r.facility),
                  if (r.doctor case final d?) d.toLowerCase().startsWith('dr') ? d : 'Dr. $d',
                ].join(' · '),
                style: LT.small,
              ),
              SizedBox(height: 2),
              Text('${SummaryView.sourceBadge(r.provenance.name, r.originalFormat).$1} · ${r.title}', style: LT.small),
              SizedBox(height: 6),
              Wrap(spacing: 16, children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => openRecord(r),
                  icon: Icon(LucideIcons.fileText, size: 16),
                  label: Text('Open report'),
                ),
                if (r.attachmentId != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => openOriginal(r),
                    icon: Icon(LucideIcons.image, size: 16),
                    label: Text(r.originalFormat == 'pdf' ? 'PDF pages' : 'Original photo'),
                  ),
                ],
              ]),
            ]),
          ),
        SizedBox(height: 28),
      ]),
    );
  }
}

/// Tiles on Records for the other tests with a trend, under the big card.
/// Tapping one puts it in the big card ([onSelect]); without [onSelect] it
/// opens that test's history.
class MoreTrends extends StatelessWidget {
  const MoreTrends({super.key, required this.series, this.onSelect, this.latest});
  final List<TrendSeries> series;
  final ValueChanged<TrendSeries>? onSelect;

  /// The most recently measured test, marked so it can be found again.
  final TrendSeries? latest;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: LayoutBuilder(builder: (context, box) {
        final half = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (i, t) in series.indexed)
          SizedBox(
              // An odd last tile spans the row instead of leaving a hole.
              width: i == series.length - 1 && series.length.isOdd ? box.maxWidth : half,
              child: ShadCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
                onTap: onSelect != null
                    ? () => onSelect!(t)
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestTrendScreen(analyte: t.analyte, unit: t.unit))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(analyteName(t.analyte), style: LT.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 6),
                    Icon(LucideIcons.chartLine, size: 16, color: LT.ink3),
                  ]),
                  SizedBox(height: 6),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: TestTrendScreen.fmt(t.points.last.$2.value), style: LT.data.copyWith(fontSize: 20, letterSpacing: -0.4)),
                      TextSpan(text: ' ${t.unit}', style: LT.meta),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text('${identical(t, latest) ? 'Latest · ' : ''}${t.points.length} results · ${_short(t.points.last.$1.effectiveDate, (latest ?? t).points.last.$1.effectiveDate.year)}', style: LT.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]);
      }),
    );
  }

  /// "22 Sep" in the year of the newest result, "22 Sep 2025" before it.
  static String _short(DateTime d, int year) => '${d.day} ${shortMonth(d)}${d.year == year ? '' : ' ${d.year}'}';
}
