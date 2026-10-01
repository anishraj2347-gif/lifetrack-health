import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../../app/test_history.dart';
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import '../widgets/summary_view.dart';
import 'originals_viewer.dart';
import 'test_trend_screen.dart';

/// Every test the profile on screen already has, to show a doctor before
/// they order one again. States age and source; never says whether a result
/// is recent enough — that is the doctor's call.
class TestsYouHaveScreen extends StatelessWidget {
  const TestsYouHaveScreen({super.key});

  static String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  static String _source(HealthRecord r) => SummaryView.sourceBadge(r.provenance.name, r.originalFormat).$1;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final h = TestHistory(s.records());
    final now = s.clock();
    int days(HealthRecord r) => now.difference(r.effectiveDate).inDays;

    Widget original(HealthRecord r) => r.attachmentId == null
        ? SizedBox.shrink()
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () async {
                final pages = await s.originals(r);
                if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OriginalsViewer(title: r.title, pages: pages)));
              },
              icon: Icon(LucideIcons.fileText, size: 16),
              label: Text(r.originalFormat == 'pdf' ? 'Open the PDF pages' : 'Open the original'),
            ),
          );

    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(eyebrow: 'Tests you already have', title: p.name, description: '${h.count} test${h.count == 1 ? '' : 's'} on this phone'),
        Note(
          'Show this to your doctor before a test is ordered again. Each result shows how old it is, which lab did it, and where it came from — whether it is recent enough is for your doctor to decide.',
          icon: LucideIcons.info,
        ),
        SizedBox(height: 12),
        if (h.isEmpty) Note('No test results yet. Add a report from Records — a photo or the lab\'s PDF.', icon: LucideIcons.fileText),
        for (final t in h.series)
          ShadCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestTrendScreen(analyte: t.analyte, unit: t.latest.$2.unit))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(analyteName(t.analyte), style: LT.label.copyWith(fontWeight: FontWeight.w600))),
                Badge2(ageOf(days(t.latest.$1)), tone: BadgeTone.outline),
                Padding(padding: EdgeInsets.only(left: 4), child: Icon(LucideIcons.chevronRight, size: 18, color: LT.inactive)),
              ]),
              SizedBox(height: 6),
              Text('${fmt(t.latest.$2.value)} ${t.latest.$2.unit}', style: LT.title.copyWith(fontSize: 22)),
              SizedBox(height: 4),
              Text(
                [
                  fullDate(t.latest.$1.effectiveDate),
                  ?(t.latest.$1.labName ?? t.latest.$1.facility),
                  _source(t.latest.$1),
                ].join(' · '),
                style: LT.small,
              ),
              original(t.latest.$1),
              if (t.points.length > 1) ...[
                SizedBox(height: 6),
                Text('Earlier', style: LT.small.copyWith(fontWeight: FontWeight.w600)),
                for (final (r, x) in t.points.skip(1).take(4))
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text('${fmt(x.value)} ${x.unit} · ${fullDate(r.effectiveDate)}${r.labName == null ? '' : ' · ${r.labName}'}', style: LT.small),
                  ),
              ],
            ]),
          ),
        if (h.documents.isNotEmpty) ...[
          Eyebrow('Scans and reports without typed values'),
          for (final r in h.documents)
            ShadCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r.title, style: LT.label.copyWith(fontWeight: FontWeight.w600))),
                  Badge2(ageOf(days(r)), tone: BadgeTone.outline),
                ]),
                SizedBox(height: 4),
                Text([fullDate(r.effectiveDate), ?(r.labName ?? r.facility), _source(r)].join(' · '), style: LT.small),
                original(r),
              ]),
            ),
        ],
        SizedBox(height: 28),
      ]),
    );
  }
}

/// Entry card: on Records and on Share.
class TestsYouHaveCard extends StatelessWidget {
  const TestsYouHaveCard({super.key, this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 12)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final h = TestHistory(s.records());
    if (h.isEmpty) return SizedBox.shrink();
    final names = [for (final t in h.series.take(3)) analyteName(t.analyte), if (h.series.length < 3) ...h.documents.take(3 - h.series.length).map((d) => d.title)];
    return ShadCard(
      margin: margin,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestsYouHaveScreen())),
      child: Row(children: [
        IconTile(LucideIcons.flaskConical),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tests you already have · ${h.count}', style: LT.label),
            SizedBox(height: 4),
            Text('${names.join(', ')}${h.count > names.length ? '…' : ''} — show your doctor before a repeat', style: LT.small),
          ]),
        ),
        Icon(LucideIcons.chevronRight, color: LT.inactive),
      ]),
    );
  }
}
