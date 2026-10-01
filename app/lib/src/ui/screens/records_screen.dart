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
        children.add(Eyebrow(m, padding: const EdgeInsets.fromLTRB(20, 18, 20, 10)));
      }
      children.add(_RecordCard(record: r));
    }

    final name = s.currentPatient?.name ?? '';
    final trends = _query.isEmpty && _filter == null ? TrendCard.all(all) : const <TrendSeries>[];
    void openTrend(TrendSeries t) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestTrendScreen(analyte: t.analyte, unit: t.unit)));
    return Column(children: [
      const FamilyBar(),
      Masthead(eyebrow: 'Records', title: name),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(LucideIcons.search, size: 18, color: LT.ink3),
            hintText: 'Search records, doctors, hospitals',
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(children: [
          for (final (label, kind) in [('All', null), ('Prescriptions', RecordKind.prescription), ('Reports', RecordKind.report), ('Scans', RecordKind.scan), ('Notes', RecordKind.note)])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip2(label, selected: _filter == kind, onTap: () => setState(() => _filter = kind)),
            ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? ListView(children: [
                if (all.isEmpty) const VitalsCard(),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const IconTile(LucideIcons.fileText, color: LT.ink3),
                    const SizedBox(height: 14),
                    Text(all.isEmpty ? 'No records yet' : 'Nothing matches', style: LT.label),
                    const SizedBox(height: 4),
                    Text(all.isEmpty ? 'Add your first prescription or report.' : 'Try another search or filter.', style: LT.small, textAlign: TextAlign.center),
                    if (all.isEmpty && AppScope.of(context).demoTools) ...[
                      const SizedBox(height: 16),
                      SlabButton('Add sample records', variant: ButtonVariant.outline, icon: LucideIcons.sparkles, onPressed: () async {
                        await AppScope.of(context).addSampleRecords();
                        if (context.mounted) AppScope.changed(context);
                      }),
                    ],
                  ]),
                ),
              ])
            : ListView(padding: const EdgeInsets.only(top: 6, bottom: 8), children: [
                if (trends.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(top: 8), child: TrendCard(series: trends.first, onTap: () => openTrend(trends.first))),
                  MoreTrends(series: trends.skip(1).toList()),
                ],
                Builder(builder: (context) {
                  final n = TestHistory(all).count;
                  return QuickTiles(
                    testsCount: n,
                    onTests: n == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TestsYouHaveScreen())),
                  );
                }),
                ...children,
              ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        child: SlabButton('Add record', icon: LucideIcons.plus, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddRecordScreen()));
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
      RecordKind.prescription => r.dose == null ? null : 'Dose ${r.dose!.display}',
      RecordKind.report => r.results.isEmpty ? null : '${r.results.length} value${r.results.length == 1 ? '' : 's'}',
      RecordKind.note => 'This phone only',
      RecordKind.scan => null,
    };
    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id))),
      child: Row(children: [
        IconTile(iconForKind(r.kind)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([kindLabel(r.kind), ?r.doctor].join(' · '), style: LT.small.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(r.title, style: LT.label.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (meta != null || r.facility != null) ...[
              const SizedBox(height: 2),
              Text([?meta, ?r.facility].join(' · '), style: LT.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(r.date.day.toString().padLeft(2, '0'), style: LT.data.copyWith(fontSize: 17)),
          Text(shortMonth(r.date), style: LT.small.copyWith(fontSize: 11)),
        ]),
      ]),
    );
  }
}
