import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_services.dart';
import '../../reminders/custom_reminder.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'reminders_screen.dart' show hm;

/// Make or change one of your own reminders. With [existing], it edits that
/// one and offers Pause and Delete.
class CustomReminderScreen extends StatefulWidget {
  const CustomReminderScreen({super.key, this.existing});
  final CustomReminder? existing;
  @override
  State<CustomReminderScreen> createState() => _CustomReminderScreenState();
}

class _CustomReminderScreenState extends State<CustomReminderScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _note = TextEditingController(text: widget.existing?.note);
  late List<(int, int)> _times = [...?widget.existing?.times];
  late Repeat _repeat = widget.existing?.repeat ?? Repeat.daily;
  late final Set<int> _days = {...?widget.existing?.days};
  late DateTime _start = widget.existing?.start ?? AppScope.of(context).clock();
  late DateTime? _end = widget.existing?.end;
  String? _error;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_times.isEmpty && widget.existing == null) {
      final now = AppScope.of(context).clock();
      _times = [((now.hour + 1) % 24, 0)];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addTime([int? replace]) async {
    final (h, m) = replace == null ? (_times.lastOrNull ?? (9, 0)) : _times[replace];
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (t == null) return;
    setState(() {
      if (replace != null) _times.removeAt(replace);
      if (!_times.contains((t.hour, t.minute))) _times.add((t.hour, t.minute));
      _times.sort((a, b) => a.$1 * 60 + a.$2 - (b.$1 * 60 + b.$2));
    });
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) {
    final now = AppScope.of(context).clock();
    final f = first ?? DateTime(now.year, now.month, now.day);
    return showDatePicker(context: context, initialDate: initial.isBefore(f) ? f : initial, firstDate: f, lastDate: DateTime(now.year + 5));
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    final r = CustomReminder(
      id: widget.existing?.id ?? AppServices.newReminderId(),
      patientId: widget.existing?.patientId ?? s.currentPatientId!,
      title: _title.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      times: _times,
      repeat: _repeat,
      days: _repeat == Repeat.weekdays ? _days : {},
      start: _start,
      end: _repeat == Repeat.once ? null : _end,
      paused: widget.existing?.paused ?? false,
    );
    final problem = r.problem();
    if (problem != null) return setState(() => _error = problem);
    setState(() => _saving = true);
    final allowed = await s.saveCustomReminder(r);
    if (!mounted) return;
    AppScope.changed(context);
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved. Notifications are not allowed for LifeTrack — allow them in the phone\'s settings to be reminded.')));
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final r = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete this reminder?'),
        content: Text('"${r.title}" will stop reminding you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).deleteCustomReminder(r);
    if (!mounted) return;
    AppScope.changed(context);
    Navigator.of(context).pop();
  }

  Future<void> _togglePause() async {
    final s = AppScope.of(context);
    await s.saveCustomReminder(widget.existing!.copyWith(paused: !widget.existing!.paused));
    if (!mounted) return;
    AppScope.changed(context);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(
          eyebrow: editing ? 'Edit reminder' : 'New reminder',
          title: editing ? widget.existing!.title : 'Remind me to…',
          trailing: editing && widget.existing!.paused ? Badge2('Paused', tone: BadgeTone.outline) : null,
        ),
        SizedBox(height: 14),
        LabeledField(
          label: 'What',
          child: TextField(
            controller: _title,
            maxLength: CustomReminder.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'e.g. Check BP, Drink water, Vitamin D', counterText: ''),
          ),
        ),
        LabeledField(
          label: 'Note (optional)',
          child: TextField(
            controller: _note,
            maxLength: CustomReminder.maxNote,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'e.g. before breakfast', counterText: ''),
          ),
        ),
        LabeledField(
          label: 'Times',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _times.length; i++)
              InputChip(
                label: Text(hm(_times[i]), style: LT.label),
                onPressed: () => _addTime(i),
                onDeleted: _times.length > 1 ? () => setState(() => _times.removeAt(i)) : null,
                deleteButtonTooltipMessage: 'Remove',
              ),
            ActionChip(avatar: Icon(LucideIcons.plus, size: 16), label: Text('Add a time'), onPressed: _addTime),
          ]),
        ),
        LabeledField(
          label: 'Repeat',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in Repeat.values) Chip2(r.label, selected: _repeat == r, onTap: () => setState(() => _repeat = r)),
          ]),
        ),
        if (_repeat == Repeat.weekdays)
          LabeledField(
            label: 'On',
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                Semantics(
                  label: CustomReminder.weekdayNames[d - 1],
                  button: true,
                  selected: _days.contains(d),
                  excludeSemantics: true,
                  child: Chip2(
                    CustomReminder.weekdayLetters[d - 1],
                    selected: _days.contains(d),
                    onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                  ),
                ),
            ]),
          ),
        LabeledField(
          label: _repeat == Repeat.once ? 'On' : 'Starting',
          child: FieldButton(
            text: fullDate(_start),
            onTap: () async {
              final d = await _pickDate(_start);
              if (d != null) setState(() => _start = d);
            },
          ),
        ),
        if (_repeat != Repeat.once)
          LabeledField(
            label: 'Until',
            hint: 'Leave it open to keep reminding until you pause or delete it.',
            child: Row(children: [
              Expanded(
                child: FieldButton(
                  text: _end == null ? 'No end date' : fullDate(_end!),
                  placeholder: _end == null,
                  onTap: () async {
                    final d = await _pickDate(_end ?? _start.add(Duration(days: 30)), first: _start);
                    if (d != null) setState(() => _end = d);
                  },
                ),
              ),
              if (_end != null) IconButton(tooltip: 'No end date', onPressed: () => setState(() => _end = null), icon: Icon(LucideIcons.x, size: 18)),
            ]),
          ),
        if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 12), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: SlabButton(editing ? 'Save changes' : 'Save reminder', icon: LucideIcons.check, onPressed: _saving ? null : _save),
        ),
        if (editing) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SlabButton(widget.existing!.paused ? 'Resume' : 'Pause', variant: ButtonVariant.outline, icon: widget.existing!.paused ? LucideIcons.play : LucideIcons.pause, onPressed: _togglePause),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SlabButton('Delete', variant: ButtonVariant.outline, icon: LucideIcons.trash2, onPressed: _delete),
          ),
        ],
        Note('Kept on this phone. A backup includes it only if you back up personal notes.', icon: LucideIcons.smartphone, margin: EdgeInsets.fromLTRB(16, 4, 16, 28)),
      ]),
    );
  }
}
