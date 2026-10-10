import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
  bool _fabHidden = false;

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
    final mq = MediaQuery.of(context);
    final body = shown.isEmpty
        ? <Widget>[
            if (all.isEmpty) VitalsCard(),
            if (all.isEmpty) PhotoBanner(Photos.report, height: 170),
            Padding(
              padding: EdgeInsets.fromLTRB(32, all.isEmpty ? 18 : 32, 32, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (all.isNotEmpty) ...[IconTile(LucideIcons.searchX, color: LT.ink3), SizedBox(height: 14)],
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
          ]
        : <Widget>[
            if (trends.isNotEmpty) ...[
              AnimatedSwitcher(
                duration: Duration(milliseconds: 220),
                child: TrendCard(key: ValueKey(key(big!)), series: big, onTap: () => openTrend(big)),
              ),
              MoreTrends(
                series: [for (final t in trends) if (!identical(t, big)) t],
                latest: trends.first,
                onSelect: (t) => setState(() => _shown = (pid!, key(t))),
              ),
            ],
            if (_query.isEmpty && _filter == null)
              Builder(builder: (context) {
                final n = TestHistory(all).count;
                return QuickTiles(
                  testsCount: n,
                  onTests: n == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TestsYouHaveScreen())),
                );
              }),
            ...children,
          ];
    // The list runs under the glass tab bar; the button floats above it and
    // steps aside while you scroll down through the records.
    return Stack(children: [
      NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          final hide = n.direction == ScrollDirection.reverse ? true : n.direction == ScrollDirection.forward ? false : _fabHidden;
          if (hide != _fabHidden) setState(() => _fabHidden = hide);
          return false;
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Masthead(eyebrow: all.isEmpty ? 'Records' : '${all.length} record${all.length == 1 ? '' : 's'}', title: name)),
          SliverToBoxAdapter(child: AuthorityBanner()),
          // Search and filters stay at hand on a strip of glass while the
          // records scroll beneath it.
          PinnedHeaderSliver(child: _SearchHeader(
            filter: _filter,
            onQuery: (v) => setState(() => _query = v.trim()),
            onFilter: (k) => setState(() => _filter = k),
          )),
          SliverPadding(
            padding: EdgeInsets.only(top: 4, bottom: mq.padding.bottom + 84),
            sliver: SliverList.list(children: [for (final (i, w) in body.indexed) Stagger(index: i, child: w)]),
          ),
        ]),
      ),
      Positioned(
        right: 16,
        bottom: mq.padding.bottom + 12,
        child: GlassFab(label: 'Add record', icon: LucideIcons.plus, hidden: _fabHidden, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddRecordScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
    ]);
  }
}

/// Search and the kind filter on a floating strip of glass.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.filter, required this.onQuery, required this.onFilter});
  final RecordKind? filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<RecordKind?> onFilter;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(LT.radiusLg + 4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.30 : 0.07), blurRadius: 20, offset: Offset(0, 6))]),
          child: Glass(
            tint: LT.ground,
            opacity: 0.74,
            radius: BorderRadius.circular(LT.radiusLg + 4),
            padding: EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: EdgeInsets.only(right: 8),
                // A solid field on the glass, so its hint is judged (and
                // read) against the field itself.
                child: GlassTone(
                  tone: LT.raised,
                  child: TextField(
                    decoration: InputDecoration(
                      fillColor: LT.raised,
                      prefixIcon: Icon(LucideIcons.search, size: 18, color: LT.ink3),
                      hintText: 'Search records, doctors, hospitals',
                    ),
                    onChanged: onQuery,
                  ),
                ),
              ),
              SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(right: 8),
                child: Row(children: [
                  for (final (label, kind) in [('All', null), ('Prescriptions', RecordKind.prescription), ('Reports', RecordKind.report), ('Scans', RecordKind.scan), ('Notes', RecordKind.note)])
                    Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Chip2(label, selected: filter == kind, dense: true, onTap: () => onFilter(kind)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      );
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
            Text(r.title, style: LT.label.copyWith(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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
