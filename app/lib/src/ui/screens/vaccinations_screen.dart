import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../vaccines/uip_schedule.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// The government (UIP) schedule for the child on screen: what was given,
/// what is due, what comes next. Tap a dose to mark it given.
class VaccinationsScreen extends StatelessWidget {
  const VaccinationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final rows = vaccineStatus(p.dateOfBirth, s.vaccinesOf(p.id), s.clock());
    final due = rows.where((r) => r.$2 == VaccineStatus.due).length;
    final given = rows.where((r) => r.$2 == VaccineStatus.given).length;
    final groups = <String, List<(VaccineDose, VaccineStatus, VaccineGiven?)>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.$1.ageLabel, () => []).add(r);
    }
    return Scaffold(
      appBar: GlassAppBar(),
      extendBodyBehindAppBar: true,
      body: ListView(children: [
        Masthead(eyebrow: 'Vaccinations', title: p.name, description: 'Born ${fullDate(p.dateOfBirth)}'),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            Badge2('$given given', tone: BadgeTone.trace),
            if (due > 0) Badge2('$due due', tone: BadgeTone.caution),
            Badge2('${rows.length - given - due} later', tone: BadgeTone.outline),
          ]),
        ),
        Note(
          'The government Universal Immunisation Programme schedule. Your child\'s doctor may follow a different one (for example the IAP schedule) — follow them where they differ, and mark here what was given.',
          icon: LucideIcons.info,
        ),
        for (final e in groups.entries) ...[
          Eyebrow(e.key),
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, (d, st, g)) in e.value.indexed)
                InkWell(
                  onTap: () => _mark(context, d, g),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(border: i == e.value.length - 1 ? null : Border(bottom: BorderSide(color: LT.rule))),
                    child: Row(children: [
                      Icon(st == VaccineStatus.given ? LucideIcons.circleCheck : LucideIcons.syringe, size: 20, color: st == VaccineStatus.given ? LT.trace : LT.ink3),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.name, style: LT.label),
                          SizedBox(height: 4),
                          Text(d.protects, style: LT.small),
                          SizedBox(height: 8),
                          // Under the name, not beside it: a full date beside a
                          // vaccine name runs off a narrow screen.
                          switch (st) {
                            VaccineStatus.given => Badge2('Given ${fullDate(g!.on)}', tone: BadgeTone.trace),
                            VaccineStatus.due => Badge2('Due since ${fullDate(d.dueDate(p.dateOfBirth))}', tone: BadgeTone.caution),
                            VaccineStatus.upcoming => Badge2(fullDate(d.dueDate(p.dateOfBirth)), tone: BadgeTone.outline),
                          },
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ],
        SizedBox(height: 28),
      ]),
    );
  }

  Future<void> _mark(BuildContext context, VaccineDose d, VaccineGiven? g) async {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final place = TextEditingController(text: g?.place ?? '');
    var on = g?.on ?? s.clock();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(d.name, style: LT.title.copyWith(fontSize: 20)),
            SizedBox(height: 4),
            Text('${d.ageLabel} · ${d.protects}', style: LT.small),
            SizedBox(height: 16),
            FieldButton(
              text: 'Given on ${fullDate(on)}',
              placeholder: false,
              onTap: () async {
                final x = await showDatePicker(context: c, initialDate: on, firstDate: p.dateOfBirth, lastDate: s.clock());
                if (x != null) set(() => on = x);
              },
            ),
            SizedBox(height: 10),
            TextField(controller: place, decoration: InputDecoration(hintText: 'Where (optional), e.g. PHC Sector 12')),
            SizedBox(height: 16),
            SlabButton('Mark as given', icon: LucideIcons.check, onPressed: () async {
              await s.markVaccine(p.id, d.code, VaccineGiven(on: on, place: place.text.trim().isEmpty ? null : place.text.trim()));
              if (!c.mounted) return;
              celebrate(c, 'Marked as given');
              Navigator.of(c).pop();
            }),
            if (g != null) ...[
              SizedBox(height: 8),
              SlabButton('Not given', variant: ButtonVariant.ghost, onPressed: () async {
                await s.markVaccine(p.id, d.code, null);
                if (c.mounted) Navigator.of(c).pop();
              }),
            ],
          ]),
        ),
      ),
    );
    if (context.mounted) AppScope.changed(context);
  }
}

/// On a child's Records: how many doses are due, one tap to the schedule.
class VaccinationsCard extends StatelessWidget {
  const VaccinationsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient;
    if (p == null || p.ageAt(s.clock()) >= 18) return SizedBox.shrink();
    final rows = vaccineStatus(p.dateOfBirth, s.vaccinesOf(p.id), s.clock());
    final due = rows.where((r) => r.$2 == VaccineStatus.due).toList();
    final next = rows.where((r) => r.$2 == VaccineStatus.upcoming).firstOrNull;
    return ShadCard(
      margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VaccinationsScreen()));
        if (context.mounted) AppScope.changed(context);
      },
      child: Row(children: [
        IconTile(LucideIcons.syringe, color: due.isEmpty ? LT.ink : LT.cautionInk, background: due.isEmpty ? LT.raised : LT.caution),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vaccinations', style: LT.label),
            SizedBox(height: 4),
            Text(
              due.isNotEmpty
                  ? '${due.length} due: ${due.take(3).map((r) => r.$1.name).join(', ')}${due.length > 3 ? '…' : ''}'
                  : next == null
                      ? 'All doses in the schedule are marked given'
                      : 'Next: ${next.$1.name} · ${fullDate(next.$1.dueDate(p.dateOfBirth))}',
              style: LT.small,
            ),
          ]),
        ),
        Icon(LucideIcons.chevronRight, color: LT.inactive),
      ]),
    );
  }
}
