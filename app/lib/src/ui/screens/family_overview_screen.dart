import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_services.dart';
import '../../family/family_role.dart';
import '../../model/custody.dart';
import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../../vaccines/uip_schedule.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/family_bar.dart';
import '../widgets/parts.dart';
import 'add_family_screen.dart';

/// Everyone on this phone, around the head of family (the phone owner):
/// grandparents and parents above, the head's own generation, children and
/// grandchildren below. Tap a person to open their records.
class FamilyOverviewScreen extends StatelessWidget {
  const FamilyOverviewScreen({super.key});

  static String lifeTrackIdText(String id) => '${id.substring(0, 4)} ${id.substring(4, 8)} ${id.substring(8)}';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final head = s.selfPatient;
    if (head == null) return const Scaffold(body: Center(child: Text('Set up your own profile first.')));
    final others = [for (final p in s.familyOnPhone()) if (p.id != head.id) p];
    FamilyRole roleOf(Patient p) => FamilyRole.parse(s.custodyOf(p.id)?.relation ?? '') ?? FamilyRole.other;
    final byGen = <int, List<Patient>>{};
    for (final p in others) {
      byGen.putIfAbsent(roleOf(p).generation, () => []).add(p);
    }
    for (final l in byGen.values) {
      l.sort((a, b) => a.dateOfBirth.compareTo(b.dateOfBirth));
    }

    Widget section(int g, String title) => byGen[g] == null
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Eyebrow(title),
            for (final p in byGen[g]!) _MemberCard(patient: p, role: roleOf(p)),
          ]);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(
          eyebrow: 'Family overview',
          title: '${head.name.split(' ').first}\'s family',
          description: '${others.length + 1} ${others.isEmpty ? 'person' : 'people'} on this phone · ${head.name} is the head of family',
        ),
        const SizedBox(height: 8),
        section(-2, 'Grandparents'),
        section(-1, 'Parents and elders'),
        const Eyebrow('Head of family'),
        _MemberCard(patient: head, role: null),
        section(0, 'Spouse, brothers and sisters'),
        section(1, 'Children'),
        section(2, 'Grandchildren'),
        if (others.isEmpty) const Note('Only you so far. Add your family below — each person keeps their own records, encrypted on this phone.', icon: LucideIcons.users),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SlabButton('Add a family member', variant: ButtonVariant.outline, icon: LucideIcons.userPlus, onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddFamilyScreen()));
            if (context.mounted) AppScope.changed(context);
          }),
        ),
        const Note(
          'Roles are how each person is related to the head of family. They do not change who can share whose records: you share for your children under 18 and for adults who asked you to, and adults can stop that at any time.',
          icon: LucideIcons.info,
          margin: EdgeInsets.fromLTRB(16, 4, 16, 28),
        ),
      ]),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.patient, required this.role});
  final Patient patient;

  /// Null for the head of family.
  final FamilyRole? role;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = patient;
    final head = role == null;
    final now = s.clock();
    final records = s.repository.recordsOf(p.id);
    final meds = records.where((r) => r.kind == RecordKind.prescription && r.dose != null && r.isActiveAt(now)).length;
    final reports = records.where((r) => r.kind == RecordKind.report).length;
    final due = p.ageAt(now) < 18 ? vaccineStatus(p.dateOfBirth, s.vaccinesOf(p.id), now).where((v) => v.$2 == VaccineStatus.due).length : 0;
    final next = s.reminderSettings.on
        ? s.reminderPlan().where((r) => r.items.any((i) => i.patient.id == p.id) || r.customFor?.id == p.id).firstOrNull
        : null;
    final id = s.lifeTrackIdOf(p.id);
    final custody = s.custodyOf(p.id);
    final viewing = s.currentPatientId == p.id;

    final fg = head ? LT.onDark : LT.ink;
    final muted = head ? LT.onDarkMuted : LT.ink3;
    final sexAge = [if (p.sex == Sex.female) 'F' else if (p.sex == Sex.male) 'M', '${p.ageAt(now)} y'].join(' · ');
    final facts = [
      '${records.length} record${records.length == 1 ? '' : 's'}',
      if (reports > 0) '$reports report${reports == 1 ? '' : 's'}',
      if (meds > 0) '$meds medicine${meds == 1 ? '' : 's'} now',
      if (due > 0) '$due vaccine${due == 1 ? '' : 's'} due',
    ];

    return ShadCard(
      color: head ? LT.primary : LT.surface,
      onTap: () async {
        await s.switchTo(p.id);
        if (!context.mounted) return;
        AppScope.changed(context);
        Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: head ? LT.accent : LT.raised,
            child: Text(FamilyBar.initials(p.name), style: const TextStyle(color: LT.ink, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: LT.label.copyWith(fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 2),
              Text('${head ? 'Head of family · you' : role!.label} · $sexAge', style: LT.small.copyWith(color: muted)),
            ]),
          ),
          if (viewing) Padding(padding: const EdgeInsets.only(left: 6), child: _Pill('Open now', dark: head, lime: true)),
          if (!head)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: muted),
              onSelected: (_) => _changeRole(context, s, custody!),
              itemBuilder: (_) => const [PopupMenuItem(value: 'role', child: Text('Change role'))],
            ),
        ]),
        const SizedBox(height: 10),
        Text(facts.join(' · '), style: LT.small.copyWith(color: fg)),
        if (next != null) ...[
          const SizedBox(height: 2),
          Text('Next reminder ${dateTime(next.at)}', style: LT.small.copyWith(color: muted)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (id != null) _Pill('ID ${FamilyOverviewScreen.lifeTrackIdText(id)}', dark: head),
          if (p.verification != null) _Pill('Verified · DigiLocker', dark: head),
          if (custody != null && custody.kind == CustodyKind.childOfParent && !custody.isVerified) _Pill('Parent declared', dark: head),
          if (custody != null && custody.kind == CustodyKind.delegatedByAdult) _Pill('Agreed in person', dark: head),
        ]),
      ]),
    );
  }

  Future<void> _changeRole(BuildContext context, AppServices s, Custody c) async {
    final choices = c.kind == CustodyKind.childOfParent ? FamilyRole.forChild : FamilyRole.forAdult;
    final picked = await showModalBottomSheet<FamilyRole>(
      context: context,
      isScrollControlled: true,
      builder: (c2) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${patient.name} is the head of family\'s…', style: LT.label.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in choices) Chip2(r.label, selected: c.relation == r.name, onTap: () => Navigator.pop(c2, r)),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null || picked.name == c.relation) return;
    await s.setRole(patient.id, picked);
    if (context.mounted) AppScope.changed(context);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.dark, this.lime = false});
  final String text;
  final bool dark;

  /// Lime means "now" in this app — the profile currently open.
  final bool lime;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: ShapeDecoration(color: lime ? LT.accent : dark ? const Color(0xFF2A2A28) : LT.raised, shape: const StadiumBorder()),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: lime ? LT.ink : dark ? LT.onDark : LT.ink2)),
      );
}
