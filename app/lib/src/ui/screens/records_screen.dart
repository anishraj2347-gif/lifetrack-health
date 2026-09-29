import 'package:flutter/material.dart';

import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'add_record_screen.dart';
import 'record_screen.dart';

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
      final first = m != month;
      if (first) {
        month = m;
        children.add(Eyebrow(m, padding: const EdgeInsets.fromLTRB(20, 16, 20, 8)));
      }
      children.add(_RecordRow(record: r, heavyRule: first));
    }

    return Column(children: [
      Masthead(
        eyebrow: 'Records',
        title: s.currentPatient?.name ?? '',
        trailing: Text('${all.length}\nRECORDS', textAlign: TextAlign.right, style: LT.eyebrow.copyWith(fontSize: 11, height: 1.5)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, color: LT.ink3),
            hintText: 'Search records',
            border: InputBorder.none,
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: LT.rule)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: LT.ink)),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(children: [
          for (final (label, kind) in [('All', null), ('Rx', RecordKind.prescription), ('Reports', RecordKind.report), ('Scans', RecordKind.scan), ('Notes', RecordKind.note)])
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: Chip2(label, selected: _filter == kind, onTap: () => setState(() => _filter = kind)),
            ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(all.isEmpty ? 'No records yet. Add your first prescription or report.' : 'Nothing matches.', style: LT.lede, textAlign: TextAlign.center),
                ),
              )
            : ListView(children: children),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SlabButton('Add record', onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddRecordScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
    ]);
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.heavyRule});
  final HealthRecord record;
  final bool heavyRule;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final meta = switch (r.kind) {
      RecordKind.prescription => 'Prescription${r.dose == null ? '' : ' · ${r.dose!.display}'}',
      RecordKind.report => r.results.isEmpty ? 'Report' : 'Report · ${r.results.length} values',
      RecordKind.scan => 'Scan',
      RecordKind.note => 'Personal note · this phone only',
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: heavyRule ? LT.ink : LT.rule, width: heavyRule ? 2 : 1))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 38,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.date.day.toString().padLeft(2, '0'), style: const TextStyle(fontFamily: LT.mono, fontSize: 19, fontWeight: FontWeight.w600, height: 1)),
              Text(shortMonth(r.date), style: const TextStyle(fontFamily: LT.mono, fontSize: 10, color: LT.ink3, letterSpacing: 1)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: LT.label.copyWith(fontSize: 17)),
              if (r.doctor != null || r.facility != null) ...[
                const SizedBox(height: 4),
                Text([r.doctor, r.facility].whereType<String>().join(' · '), style: LT.small),
              ],
              const SizedBox(height: 5),
              Text(meta.toUpperCase(), style: LT.eyebrow.copyWith(letterSpacing: 1.2)),
            ]),
          ),
        ]),
      ),
    );
  }
}
