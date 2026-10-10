import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/health_record.dart';
import '../app_scope.dart';
import '../../app/test_history.dart';
import 'tests_you_have_screen.dart';
import 'test_trend_screen.dart';
import 'vitals_screen.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import '../widgets/family_bar.dart';
import '../widgets/trend_card.dart';
import 'add_record_screen.dart';
import 'record_screen.dart';

IconData iconForKind(RecordKind k) => switch (k) {
      RecordKind.prescription => LucideIcons.pill,
      RecordKind.report => LucideIcons.flaskConical,
      RecordKind.scan => LucideIcons.scanLine,
      RecordKind.note => LucideIcons.stickyNote,
    };

String kindLabel(RecordKind k) => switch (k) {
      RecordKind.prescription => 'Prescription',
      RecordKind.report => 'Report',
      RecordKind.scan => 'Scan',
      RecordKind.note => 'Note',
    };

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  RecordKind? _filter;
  String _query = '';

  /// The test in the big trend card: (profile, analyte|unit). Null shows the
  /// most recently measured.
  (String, String)? _shown;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final all = s.records();
    final shown = all.where((r) {
      if (_filter != null && r.kind != _filter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return r.title.toLowerCase().contains(q) ||
          (r.doctor ?? '').toLowerCase().contains(q) ||
          (r.facility ?? '').toLowerCase().contains(q);
    }).toList();

    final children = <Widget>[];
    String? month;
    for (final r in shown) {
      final m = monthYear(r.date);
      if (m != month) {
        month = m;
        children.add(Eyebrow(m, padding: EdgeInsets.fromLTRB(20, 18, 20, 10)));
      }
      children.add(_RecordCard(record: r));
    }

    final name = s.currentPatient?.name ?? '';
    final trends = _query.isEmpty && _filter == null ? TrendCard.all(all) : <TrendSeries>[];
    String key(TrendSeries t) => '${t.analyte}|${t.unit}';
    final pid = s.currentPatientId;
    final big = trends.where((t) => _shown != null && _shown!.$1 == pid && _shown!.$2 == key(t)).firstOrNull ?? trends.firstOrNull;
    void openTrend(TrendSeries t) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestTrendScreen(analyte: t.analyte, unit: t.unit)));
    return Column(children: [
      FamilyBar(),
      Masthead(eyebrow: 'Records', title: name),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: Icon(LucideIcons.search, size: 18, color: LT.ink3),
            hintText: 'Search records, doctors, hospitals',
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(children: [
          for (final (label, kind) in [('All', null), ('Prescriptions', RecordKind.prescription), ('Reports', RecordKind.report), ('Scans', RecordKind.scan), ('Notes', RecordKind.note)])
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip2(label, selected: _filter == kind, onTap: () => setState(() => _filter = kind)),
            ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? ListView(children: [
                if (all.isEmpty) VitalsCard(),
                if (all.isEmpty) PhotoBanner(Photos.report, height: 170),
                Padding(
                  padding: EdgeInsets.fromLTRB(32, all.isEmpty ? 18 : 32, 32, 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (all.isNotEmpty) ...[IconTile(LucideIcons.fileText, color: LT.ink3), SizedBox(height: 14)],
                    Text(all.isEmpty ? 'No records yet' : 'Nothing matches', style: LT.label),
                    SizedBox(height: 4),
                    Text(all.isEmpty ? 'Add your first prescription or report.' : 'Try another search or filter.', style: LT.small, textAlign: TextAlign.center),
                    if (all.isEmpty && AppScope.of(context).demoTools) ...[
                      SizedBox(height: 16),
                      SlabButton('Add sample records', variant: ButtonVariant.outline, icon: LucideIcons.sparkles, onPressed: () async {
                        await AppScope.of(context).addSampleRecords();
                        if (context.mounted) AppScope.changed(context);
                      }),
                    ],
                  ]),
                ),
              ])
            : ListView(padding: EdgeInsets.only(top: 6, bottom: 8), children: [
                if (trends.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: 220),
                      child: TrendCard(key: ValueKey(key(big!)), series: big, onTap: () => openTrend(big)),
                    ),
                  ),
                  MoreTrends(
                    series: [for (final t in trends) if (!identical(t, big)) t],
                    latest: trends.first,
                    onSelect: (t) => setState(() => _shown = (pid!, key(t))),
                  ),
                ],
                Builder(builder: (context) {
                  final n = TestHistory(all).count;
                  return QuickTiles(
                    testsCount: n,
                    onTests: n == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestsYouHaveScreen())),
                  );
                }),
                ...children,
              ]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: SlabButton('Add record', icon: LucideIcons.plus, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddRecordScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
    ]);
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final HealthRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final meta = switch (r.kind) {
      RecordKind.prescription => r.dose != null ? 'Dose ${r.dose!.display}' : r.source == RecordSource.typedByPatient ? 'Only when needed' : null,
      RecordKind.report => r.results.isEmpty ? null : '${r.results.length} value${r.results.length == 1 ? '' : 's'}',
      RecordKind.note => 'This phone only',
      RecordKind.scan => null,
    };
    return ShadCard(
      padding: EdgeInsets.fromLTRB(14, 14, 16, 14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id))),
      child: Row(children: [
        IconTile(iconForKind(r.kind)),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([kindLabel(r.kind), ?r.doctor].join(' · '), style: LT.small.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 2),
            Text(r.title, style: LT.label.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (meta != null || r.facility != null) ...[
              SizedBox(height: 2),
              Text([?meta, ?r.facility].join(' · '), style: LT.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(r.date.day.toString().padLeft(2, '0'), style: LT.data.copyWith(fontSize: 17)),
          Text(shortMonth(r.date), style: LT.small.copyWith(fontSize: 12)),
        ]),
      ]),
    );
  }
}
