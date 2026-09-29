import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
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
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final trend = _query.isEmpty && _filter == null ? TrendCard.pick(all) : null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: LT.accent, shape: BoxShape.circle),
            child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
          ),
          const SizedBox(width: 8),
          RoundButton(LucideIcons.plus, onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family profiles arrive in a later version.')));
          }),
          const Spacer(),
          Badge2(s.isDemo ? 'Sample data' : '${all.length} records', tone: s.isDemo ? BadgeTone.caution : BadgeTone.neutral),
        ]),
      ),
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
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const IconTile(LucideIcons.fileText, color: LT.ink3),
                    const SizedBox(height: 14),
                    Text(all.isEmpty ? 'No records yet' : 'Nothing matches', style: LT.label),
                    const SizedBox(height: 4),
                    Text(all.isEmpty ? 'Add your first prescription or report.' : 'Try another search or filter.', style: LT.small, textAlign: TextAlign.center),
                  ]),
                ),
              )
            : ListView(padding: const EdgeInsets.only(top: 6, bottom: 8), children: [
                if (trend != null) Padding(padding: const EdgeInsets.only(top: 8), child: trend),
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
