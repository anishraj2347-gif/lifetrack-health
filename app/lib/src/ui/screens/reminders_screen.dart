import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../reminders/reminder_plan.dart';
import '../app_scope.dart';
import '../widgets/family_bar.dart';
import 'vaccinations_screen.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// Me → Medicine reminders: on/off, the three times, and whether medicine
/// names may show on the lock screen.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String? _note;

  static String hm((int, int) t) {
    final (h, m) = t;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _set(ReminderSettings next) async {
    final s = AppScope.of(context);
    final ok = await s.setReminders(next);
    if (!mounted) return;
    setState(() => _note = ok ? null : 'Notifications are not allowed for LifeTrack. Allow them in the phone\'s settings, then try again.');
    AppScope.changed(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final st = s.reminderSettings;
    final plan = st.on ? s.reminderPlan().take(5).toList() : const <PlannedReminder>[];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(
          eyebrow: 'Medicine reminders',
          title: st.on ? 'Reminders are on' : 'Remind me to take my medicines',
          trailing: Badge2(st.on ? 'On' : 'Off', tone: st.on ? BadgeTone.trace : BadgeTone.outline),
        ),
        const SizedBox(height: 14),
        if (s.reminderScheduler == null)
          const Note('Reminders are not available in this build.', icon: LucideIcons.bellOff)
        else ...[
          ShadCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const IconTile(LucideIcons.bell),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Remind me', style: LT.label),
                  SizedBox(height: 4),
                  Text('From the dose on each current prescription, for everyone on this phone. Stops when a course ends.', style: LT.small),
                ]),
              ),
              Switch(value: st.on, onChanged: (v) => _set(st.copyWith(on: v))),
            ]),
          ),
          if (_note != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text(_note!, style: LT.small.copyWith(color: LT.signal))),
          const Eyebrow('When'),
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final slot in DoseSlot.values)
                ListTile(
                  leading: Icon(switch (slot) { DoseSlot.morning => LucideIcons.sunrise, DoseSlot.afternoon => LucideIcons.sun, DoseSlot.night => LucideIcons.moon }, color: LT.ink2),
                  title: Text(slot.label, style: LT.label),
                  trailing: Text(hm(st.times[slot]!), style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final (h, m) = st.times[slot]!;
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
                    if (t != null) await _set(st.copyWith(times: {...st.times, slot: (t.hour, t.minute)}));
                  },
                ),
            ]),
          ),
          ShadCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Show medicine names', style: LT.label),
                  SizedBox(height: 4),
                  Text('Off: the notification only says it is time for your medicines — anyone who sees your lock screen learns nothing more.', style: LT.small),
                ]),
              ),
              Switch(value: st.showNames, onChanged: (v) => _set(st.copyWith(showNames: v))),
            ]),
          ),
          if (st.on) ...[
            const Eyebrow('Coming up'),
            if (plan.isEmpty) const Note('Nothing to remind: no current prescription has a dose set.', icon: LucideIcons.info, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
            for (final r in plan)
              ShadCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.slot.label} · ${dateTime(r.at)}', style: LT.small),
                  const SizedBox(height: 4),
                  Text(r.body(showNames: true, selfPatientId: s.selfPatientId), style: LT.label),
                ]),
              ),
          ],
          const SizedBox(height: 28),
        ],
      ]),
    );
  }
}

/// Today's doses for the profile on screen, to tick off. The record of what
/// was taken stays on this phone.
class TodaysMedicines extends StatelessWidget {
  const TodaysMedicines({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final doses = s.todaysDoses();
    if (doses.isEmpty) return const SizedBox.shrink();
    final st = s.reminderSettings;
    return ShadCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text("Today's medicines", style: LT.label)),
          if (!st.on && s.reminderScheduler != null)
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RemindersScreen()));
                if (context.mounted) AppScope.changed(context);
              },
              icon: const Icon(LucideIcons.bell, size: 16),
              label: const Text('Remind me'),
            ),
        ]),
        for (final slot in DoseSlot.values)
          if (doses.where((d) => d.$1 == slot).toList() case final list when list.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${slot.label} · ${_RemindersScreenState.hm(st.times[slot]!)}', style: LT.small.copyWith(fontWeight: FontWeight.w600)),
            for (final (_, r, n) in list)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: s.takenToday(slot, r.id),
                title: Text('${r.title}${n > 1 ? ' ×$n' : ''}', style: LT.label),
                onChanged: (v) async {
                  await s.markTaken(slot, r.id, v ?? false);
                  if (context.mounted) AppScope.changed(context);
                },
              ),
          ],
      ]),
    );
  }
}

/// First tab: what to take today, vaccinations due, and what is coming up —
/// for the profile on screen, with the settings one tap away.
class RemindersTab extends StatelessWidget {
  const RemindersTab({super.key});

  Future<void> _settings(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RemindersScreen()));
    if (context.mounted) AppScope.changed(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient;
    final st = s.reminderSettings;
    final available = s.reminderScheduler != null;
    final doses = s.todaysDoses();
    final child = p != null && p.ageAt(s.clock()) < 18;
    final coming = st.on ? s.reminderPlan().take(6).toList() : const <PlannedReminder>[];
    final times = [
      for (final slot in DoseSlot.values)
        if (doses.any((d) => d.$1 == slot)) '${slot.label} ${_RemindersScreenState.hm(st.times[slot]!)}',
    ];
    return Column(children: [
      const FamilyBar(),
      Masthead(
        eyebrow: 'Reminders',
        title: p?.name ?? '',
        trailing: available ? Badge2(st.on ? 'On' : 'Off', tone: st.on ? BadgeTone.trace : BadgeTone.outline) : null,
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(top: 6, bottom: 96), children: [
          if (available)
            ShadCard(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              onTap: () => _settings(context),
              child: Row(children: [
                IconTile(st.on ? LucideIcons.bellRing : LucideIcons.bellOff),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(st.on ? 'Medicine reminders are on' : 'Medicine reminders are off', style: LT.label),
                    const SizedBox(height: 4),
                    Text(
                      st.on
                          ? (times.isEmpty ? 'Times, and whether names show on the lock screen' : times.join(' · '))
                          : 'Tap to have the phone remind you at the times you choose',
                      style: LT.small,
                    ),
                  ]),
                ),
                const Icon(LucideIcons.chevronRight, color: LT.inactive),
              ]),
            ),
          const TodaysMedicines(),
          if (child) const VaccinationsCard(),
          if (doses.isEmpty && !child)
            const Note(
              'Nothing to take today. Reminders come from prescriptions that have a dose — add one in Records, and it shows here.',
              icon: LucideIcons.pill,
            ),
          if (coming.isNotEmpty) ...[
            const Eyebrow('Coming up'),
            for (final r in coming)
              ShadCard(
                child: Row(children: [
                  Icon(r.vaccine != null ? LucideIcons.syringe : switch (r.slot) { DoseSlot.morning => LucideIcons.sunrise, DoseSlot.afternoon => LucideIcons.sun, DoseSlot.night => LucideIcons.moon }, size: 18, color: LT.ink2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.title} · ${dateTime(r.at)}', style: LT.small),
                      const SizedBox(height: 4),
                      Text(r.body(showNames: true, selfPatientId: s.selfPatientId), style: LT.label),
                    ]),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    ]);
  }
}
