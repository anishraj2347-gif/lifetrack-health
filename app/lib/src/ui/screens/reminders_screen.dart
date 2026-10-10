import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_services.dart';
import '../../reminders/reminder_plan.dart';
import '../app_scope.dart';
import '../widgets/family_bar.dart';
import '../../reminders/custom_reminder.dart';
import 'custom_reminder_screen.dart';
import 'record_screen.dart';
import 'vaccinations_screen.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// 8:00 AM, 9:00 PM.
String hm((int, int) t) {
  final (h, m) = t;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Me → Medicine reminders: on/off, the three times, and whether medicine
/// names may show on the lock screen.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String? _note;

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
    final plan = st.on ? s.reminderPlan().take(5).toList() : <PlannedReminder>[];
    return Scaffold(
      appBar: GlassAppBar(),
      extendBodyBehindAppBar: true,
      body: ListView(children: [
        Masthead(
          eyebrow: 'Reminder settings',
          title: st.on ? 'Reminders are on' : 'Remind me',
          trailing: Badge2(st.on ? 'On' : 'Off', tone: st.on ? BadgeTone.trace : BadgeTone.outline),
        ),
        SizedBox(height: 14),
        if (s.reminderScheduler == null)
          Note('Reminders are not available in this build.', icon: LucideIcons.bellOff)
        else ...[
          ShadCard(
            padding: EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              IconTile(LucideIcons.bell),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Remind me', style: LT.label),
                  SizedBox(height: 4),
                  Text('Medicines from the dose on each current prescription (stops when a course ends), children\'s vaccinations, and the reminders you make — for everyone on this phone.', style: LT.small),
                ]),
              ),
              Switch(value: st.on, onChanged: (v) => _set(st.copyWith(on: v))),
            ]),
          ),
          if (_note != null) Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text(_note!, style: LT.small.copyWith(color: LT.signal))),
          Eyebrow('When'),
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
            padding: EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Expanded(
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
            Eyebrow('Coming up'),
            if (plan.isEmpty) Note('Nothing to remind yet: no prescription with a dose, and no reminders of your own.', icon: LucideIcons.info, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
            for (final r in plan)
              ShadCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.slot.label} · ${dateTime(r.at)}', style: LT.small),
                  SizedBox(height: 4),
                  Text(r.body(showNames: true, selfPatientId: s.selfPatientId), style: LT.label),
                ]),
              ),
          ],
          SizedBox(height: 28),
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
    if (doses.isEmpty) return SizedBox.shrink();
    final st = s.reminderSettings;
    return ShadCard(
      margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text("Today's medicines", style: LT.label)),
          if (!st.on && s.reminderScheduler != null)
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RemindersScreen()));
                if (context.mounted) AppScope.changed(context);
              },
              icon: Icon(LucideIcons.bell, size: 16),
              label: Text('Remind me'),
            ),
        ]),
        for (final slot in DoseSlot.values)
          if (doses.where((d) => d.$1 == slot).toList() case final list when list.isNotEmpty) ...[
            SizedBox(height: 8),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: [
              Text('${slot.label} · ${hm(st.times[slot]!)}', style: LT.small.copyWith(fontWeight: FontWeight.w600)),
              if (slot == nowSlot(st.times, s.clock())) NowTag(),
            ]),
            for (final (_, r, n) in list)
              SwipeToggle(
                key: ValueKey('dose-${slot.name}-${r.id}'),
                done: s.takenToday(slot, r.id),
                onToggle: (v) => tickAndMaybeCelebrate(context, () => s.markTaken(slot, r.id, v), v),
                child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: s.takenToday(slot, r.id),
                title: _Struck('${r.title}${n > 1 ? ' ×$n' : ''}', done: s.takenToday(slot, r.id)),
                secondary: IconButton(
                  tooltip: 'Edit ${r.title}',
                  icon: Icon(LucideIcons.pencil, size: 17, color: LT.ink3),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordScreen(recordId: r.id)));
                    if (context.mounted) AppScope.changed(context);
                  },
                ),
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  tickAndMaybeCelebrate(context, () => s.markTaken(slot, r.id, v ?? false), v ?? false);
                },
              ),
              ),
          ],
        // Shown until the first tick of the day; after that it is known.
        if (doses.length > 1 && !doses.any((d) => s.takenToday(d.$1, d.$2.id)))
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Tip: swipe a medicine sideways to tick it.', style: LT.small),
          ),
      ]),
    );
  }
}

/// First tab: what to take today, vaccinations due, and what is coming up —
/// for the profile on screen, with the settings one tap away.
class RemindersTab extends StatelessWidget {
  const RemindersTab({super.key});

  Future<void> _open(BuildContext context, CustomReminder? c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomReminderScreen(existing: c)));
    if (context.mounted) AppScope.changed(context);
  }

  Future<void> _settings(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RemindersScreen()));
    if (context.mounted) AppScope.changed(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient;
    final st = s.reminderSettings;
    final available = s.reminderScheduler != null;
    final doses = s.todaysDoses();
    final today = s.todaysCustom();
    final mine = p == null ? <CustomReminder>[] : s.customRemindersOf(p.id);
    final child = p != null && p.ageAt(s.clock()) < 18;
    final coming = st.on ? s.reminderPlan().take(6).toList() : <PlannedReminder>[];
    final times = [
      for (final slot in DoseSlot.values)
        if (doses.any((d) => d.$1 == slot)) '${slot.label} ${hm(st.times[slot]!)}',
    ];
    return Column(children: [
      Masthead(
        eyebrow: _today(s.clock()),
        title: p?.name ?? '',
        trailing: available ? Badge2(st.on ? 'On' : 'Off', tone: st.on ? BadgeTone.trace : BadgeTone.outline) : null,
      ),
      AuthorityBanner(),
      Expanded(
        child: ListView(padding: EdgeInsets.only(top: 6, bottom: 96), children: [
          TodayHero(),
          if (available)
            ShadCard(
              margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
              onTap: () => _settings(context),
              child: Row(children: [
                IconTile(st.on ? LucideIcons.bellRing : LucideIcons.bellOff),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(st.on ? 'Reminders are on' : 'Reminders are off', style: LT.label),
                    SizedBox(height: 4),
                    Text(
                      st.on
                          ? (times.isEmpty ? 'Times, and whether names show on the lock screen' : times.join(' · '))
                          : 'Tap to have the phone remind you at the times you choose',
                      style: LT.small,
                    ),
                  ]),
                ),
                Icon(LucideIcons.chevronRight, color: LT.inactive),
              ]),
            ),
          TodaysMedicines(),
          if (today.isNotEmpty)
            ShadCard(
              margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Today's reminders", style: LT.label),
                SizedBox(height: 4),
                for (final (h, m, c) in today)
                  SwipeToggle(
                    key: ValueKey('custom-${c.id}-$h-$m'),
                    done: s.customDoneToday(c, h, m),
                    doneLabel: 'Done',
                    onToggle: (v) => tickAndMaybeCelebrate(context, () => s.markCustomDone(c, h, m, v), v),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: s.customDoneToday(c, h, m),
                      title: _Struck(c.title, done: s.customDoneToday(c, h, m)),
                      subtitle: Text([hm((h, m)), ?c.note].join(' · '), style: LT.small),
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        tickAndMaybeCelebrate(context, () => s.markCustomDone(c, h, m, v ?? false), v ?? false);
                      },
                    ),
                  ),
              ]),
            ),
          if (child) VaccinationsCard(),
          if (doses.isEmpty && today.isEmpty && !child) PhotoBanner(Photos.pills, height: 160),
          if (doses.isEmpty && today.isEmpty && !child)
            Note(
              'Nothing for today. Medicines with a dose in Records show here, and so do reminders you make below.',
              icon: LucideIcons.pill,
            ),
          Eyebrow('Your reminders${mine.isEmpty ? '' : ' · ${mine.length}'}'),
          for (final c in mine)
            ShadCard(
              onTap: () => _open(context, c),
              child: Row(children: [
                IconTile(c.paused ? LucideIcons.pause : LucideIcons.alarmClock, color: c.paused ? LT.ink3 : LT.ink),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.title, style: LT.label.copyWith(color: c.paused ? LT.ink3 : null)),
                    SizedBox(height: 4),
                    Text('${c.paused ? 'Paused · ' : ''}${c.times.map(hm).join(', ')} · ${c.scheduleLabel(fullDate)}', style: LT.small),
                  ]),
                ),
                Icon(LucideIcons.chevronRight, color: LT.inactive),
              ]),
            ),
          if (p != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SlabButton('Create a reminder', variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => _open(context, null)),
            ),
          if (coming.isNotEmpty) ...[
            Eyebrow('Coming up'),
            ShadCard(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final (i, r) in coming.indexed)
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(border: i == coming.length - 1 ? null : Border(bottom: BorderSide(color: LT.rule))),
                    child: Row(children: [
                      Icon(r.vaccine != null ? LucideIcons.syringe : r.custom != null ? LucideIcons.alarmClock : switch (r.slot) { DoseSlot.morning => LucideIcons.sunrise, DoseSlot.afternoon => LucideIcons.sun, DoseSlot.night => LucideIcons.moon }, size: 18, color: LT.ink2),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.body(showNames: true, selfPatientId: s.selfPatientId), style: LT.label),
                          SizedBox(height: 2),
                          Text('${r.title} · ${dateTime(r.at)}', style: LT.meta),
                        ]),
                      ),
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

/// A to-do title that fades and is struck through once ticked.
class _Struck extends StatelessWidget {
  const _Struck(this.text, {required this.done});
  final String text;
  final bool done;
  @override
  Widget build(BuildContext context) => AnimatedDefaultTextStyle(
        duration: Duration(milliseconds: 200),
        style: LT.label.copyWith(
          color: done ? LT.ink3 : LT.ink,
          decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
          decorationColor: LT.ink3,
        ),
        child: Text(text),
      );
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Friday, 10 October" — the eyebrow on the home tab.
String _today(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// The dose slot happening now: the latest whose time has come (morning
/// before the first). Lime "Now" marks it — lime means "now".
DoseSlot nowSlot(Map<DoseSlot, (int, int)> times, DateTime now) {
  var current = DoseSlot.morning;
  for (final slot in DoseSlot.values) {
    final (h, m) = times[slot]!;
    if (now.hour * 60 + now.minute >= h * 60 + m) current = slot;
  }
  return current;
}

/// Ticks one item and, when it was the last one left today, celebrates.
Future<void> tickAndMaybeCelebrate(BuildContext context, Future<void> Function() tick, bool nowDone) async {
  final s = AppScope.of(context);
  await tick();
  if (!context.mounted) return;
  AppScope.changed(context);
  if (!nowDone) return;
  final (done, total) = _progress(s);
  if (total > 0 && done == total) celebrate(context, 'All done for today');
}

(int, int) _progress(AppServices s) {
  final doses = s.todaysDoses();
  final custom = s.todaysCustom();
  final done = doses.where((d) => s.takenToday(d.$1, d.$2.id)).length + custom.where((c) => s.customDoneToday(c.$3, c.$1, c.$2)).length;
  return (done, doses.length + custom.length);
}

/// Home moment: a glossy black card with a ring of today's progress, what is
/// next, or "All done for today". The ring is white, not a status colour.
class TodayHero extends StatelessWidget {
  const TodayHero({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final (done, total) = _progress(s);
    if (total == 0) return SizedBox.shrink();
    final st = s.reminderSettings;
    final now = s.clock();
    String? next;
    for (final slot in DoseSlot.values) {
      final (h, m) = st.times[slot]!;
      final pending = s.todaysDoses().where((d) => d.$1 == slot && !s.takenToday(slot, d.$2.id));
      if (pending.isNotEmpty && h * 60 + m >= now.hour * 60 + now.minute) {
        next = '${slot.label} · ${hm((h, m))}';
        break;
      }
    }
    final all = done == total;
    return ShadCard(
      color: LT.primary,
      margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: EdgeInsets.all(18),
      child: Row(children: [
        SizedBox(
          width: 64,
          height: 64,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: done / total),
            duration: Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(
              painter: _RingPainter(v, LT.onDark, LT.onDarkChip),
              child: Center(child: Text('$done/$total', style: TextStyle(fontFamily: LT.body, fontSize: 16, fontWeight: FontWeight.w700, color: LT.onDark))),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(all ? 'All done for today' : '$done of $total done today', style: TextStyle(fontFamily: LT.body, fontSize: 17, fontWeight: FontWeight.w600, color: LT.onDark)),
            SizedBox(height: 4),
            Text(all ? 'Nothing left to take or do.' : next == null ? 'Tick each one as you go.' : 'Next: $next', style: TextStyle(fontFamily: LT.body, fontSize: 14, color: LT.onDarkMuted)),
          ]),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.ink, this.track);
  final double value;
  final Color ink, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(r, 0, 6.2832, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track);
    if (value > 0) {
      canvas.drawArc(r, -1.5708, 6.2832 * value, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = ink);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.ink != ink;
}

/// The small lime "Now" tag beside the current dose time.
class NowTag extends StatelessWidget {
  const NowTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(left: 8),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: LT.accent, borderRadius: BorderRadius.circular(99)),
        child: Text('Now', style: TextStyle(fontFamily: LT.body, fontSize: 12, fontWeight: FontWeight.w700, color: LT.onAccent)),
      );
}
