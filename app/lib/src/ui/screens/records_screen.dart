import 'package:flutter/material.dart';
import '../../ai/plane_a/reference_ranges.dart' show analyteName;
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
        children.add(_MonthHeader(m, shown.where((x) => monthYear(x.date) == m).length));
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
    final chips = <Widget>[
      if (r.kind == RecordKind.prescription && r.dose != null) _DosePills(r.dose!),
      if (r.kind == RecordKind.prescription && r.dose == null && r.source == RecordSource.typedByPatient) _MiniChip('Only when needed', icon: LucideIcons.clock),
      if (r.kind == RecordKind.report && r.results.isNotEmpty)
        _MiniChip('${analyteName(r.results.first.analyte)} ${TestTrendScreen.fmt(r.results.first.value)} ${r.results.first.unit}${r.results.length > 1 ? '  +${r.results.length - 1}' : ''}'),
      if (r.kind == RecordKind.note) _MiniChip('This phone only', icon: LucideIcons.lock),
    ];
    // Where it came from, as small icons on the doctor line (read out by
    // screen readers) rather than more chips.
    final marks = <(IconData, String)>[
      if (r.source == RecordSource.doctorIssued || r.source == RecordSource.labSigned) (LucideIcons.badgeCheck, 'Signed'),
      if (r.source == RecordSource.smartCapture) (LucideIcons.scanText, 'Scanned'),
      if (r.attachmentId != null) (LucideIcons.paperclip, 'Original attached'),
    ];
    return MergeSemantics(
      child: ShadCard(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _KindTile(r.kind),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: LT.label.copyWith(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              SizedBox(height: 3),
              Row(children: [
                Icon(r.doctor != null ? LucideIcons.stethoscope : LucideIcons.tag, size: 13, color: LT.ink3),
                SizedBox(width: 5),
                Expanded(
                  child: Text([r.doctor ?? kindLabel(r.kind), ?r.facility].join(' · '), style: LT.meta.copyWith(color: LT.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                for (final (icon, label) in marks)
                  Padding(padding: EdgeInsets.only(left: 6), child: Semantics(label: label, child: Icon(icon, size: 14, color: LT.ink2))),
              ]),
              if (chips.isNotEmpty) ...[
                SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ]),
          ),
          SizedBox(width: 10),
          _DateBlock(r.date),
        ]),
      ),
    );
  }
}

/// The record type as a soft tinted square with its icon.
class _KindTile extends StatelessWidget {
  const _KindTile(this.kind);
  final RecordKind kind;
  @override
  Widget build(BuildContext context) {
    final tint = LT.kindTint(kind.index);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.alphaBlend(Colors.white.withValues(alpha: LT.dark ? 0.06 : 0.35), tint), tint]),
        border: Border.all(color: Colors.white.withValues(alpha: LT.dark ? 0.08 : 0.8)),
        boxShadow: [BoxShadow(color: tint.withValues(alpha: LT.dark ? 0.0 : 0.6), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Icon(iconForKind(kind), size: 21, color: LT.ink),
    );
  }
}

/// "SEP / 22" like a calendar leaf; the year only when it is not this year.
class _DateBlock extends StatelessWidget {
  const _DateBlock(this.d);
  final DateTime d;
  @override
  Widget build(BuildContext context) {
    final thisYear = AppScope.of(context).clock().year == d.year;
    return Container(
      width: 48,
      padding: EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: LT.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: LT.dark ? 0.06 : 0.9)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(shortMonth(d).toUpperCase(), style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: LT.ink2)),
        Text('${d.day}', style: LT.data.copyWith(fontSize: 18, height: 1.15)),
        if (!thisYear) Text('${d.year}', style: LT.meta),
      ]),
    );
  }
}

/// A small neutral pill: a value, a source, a fact about the record.
class _MiniChip extends StatelessWidget {
  const _MiniChip(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: LT.raised, borderRadius: BorderRadius.circular(99), border: Border.all(color: LT.rule.withValues(alpha: 0.6))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: LT.ink2), SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w500, color: LT.ink2))),
        ]),
      );
}

/// Morning · afternoon · night as three small pills; a time with no dose is
/// faint, so the pattern (1-0-1) reads at a glance.
class _DosePills extends StatelessWidget {
  const _DosePills(this.dose);
  final Dose dose;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Dose: ${dose.morning} morning, ${dose.afternoon} afternoon, ${dose.night} night',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (n, icon) in [(dose.morning, LucideIcons.sunrise), (dose.afternoon, LucideIcons.sun), (dose.night, LucideIcons.moon)]) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: n > 0 ? LT.button : LT.raised,
                borderRadius: BorderRadius.circular(99),
                border: n > 0 ? null : Border.all(color: LT.rule.withValues(alpha: 0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: n > 0 ? LT.onButton : LT.ink3),
                SizedBox(width: 4),
                Text('$n', style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w700, color: n > 0 ? LT.onButton : LT.ink3)),
              ]),
            ),
          ],
        ]),
      );
}

/// The month a group of records falls in, as a small glass pill with how
/// many records it holds — a clear break in a long list.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.month, this.count);
  final String month;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(children: [
          Container(
            padding: EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: LT.raised,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: LT.dark ? 0.07 : 0.9)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.25 : 0.05), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.calendarDays, size: 14, color: LT.ink2),
              SizedBox(width: 6),
              Text(month, style: TextStyle(fontFamily: LT.body, fontSize: 14, fontWeight: FontWeight.w600, color: LT.ink)),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: LT.button, borderRadius: BorderRadius.circular(99)),
                child: Text('$count', style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w700, color: LT.onButton)),
              ),
            ]),
          ),
          SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: LT.rule.withValues(alpha: 0.7))),
        ]),
      );
}
