/// A reminder the patient made themselves — "Check BP", "Drink water", a
/// medicine with no prescription. Kept on this phone with the profile; in the
/// backup only when personal notes are (#6), since its words are the
/// patient's own.
enum Repeat {
  daily('Every day'),
  weekdays('Some days'),
  once('Once');

  const Repeat(this.label);
  final String label;
}

class CustomReminder {
  const CustomReminder({
    required this.id,
    required this.patientId,
    required this.title,
    this.note,
    required this.times,
    this.repeat = Repeat.daily,
    this.days = const {},
    required this.start,
    this.end,
    this.paused = false,
  });

  final String id;
  final String patientId;
  final String title;
  final String? note;

  /// Times of day, (hour, minute), sorted.
  final List<(int, int)> times;
  final Repeat repeat;

  /// For [Repeat.weekdays]: DateTime.monday … DateTime.sunday.
  final Set<int> days;

  /// First day (for [Repeat.once], the only day).
  final DateTime start;

  /// Last day, inclusive; null runs until paused or deleted.
  final DateTime? end;
  final bool paused;

  static const maxTitle = 60;
  static const maxNote = 200;
  static const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  bool occursOn(DateTime day) {
    if (paused) return false;
    final d = _date(day);
    if (d.isBefore(_date(start))) return false;
    if (end != null && d.isAfter(_date(end!))) return false;
    return switch (repeat) {
      Repeat.daily => true,
      Repeat.weekdays => days.contains(d.weekday),
      Repeat.once => d == _date(start),
    };
  }

  /// "Every day", "Mon, Wed, Fri", "Once on 3 Oct 2026" — the caller adds times.
  String scheduleLabel(String Function(DateTime) date) => switch (repeat) {
        Repeat.daily => 'Every day${end == null ? '' : ' until ${date(end!)}'}',
        Repeat.weekdays => '${days.length == 7 ? 'Every day' : [for (var i = 1; i <= 7; i++) if (days.contains(i)) weekdayNames[i - 1]].join(', ')}${end == null ? '' : ' until ${date(end!)}'}',
        Repeat.once => 'Once on ${date(start)}',
      };

  CustomReminder copyWith({bool? paused}) => CustomReminder(
        id: id, patientId: patientId, title: title, note: note, times: times, repeat: repeat, days: days, start: start, end: end, paused: paused ?? this.paused);

  Map<String, Object?> toJson() => {
        'id': id,
        'patientId': patientId,
        'title': title,
        'note': note,
        'times': [for (final (h, m) in times) [h, m]],
        'repeat': repeat.name,
        'days': days.toList()..sort(),
        'start': start.toIso8601String().substring(0, 10),
        'end': end?.toIso8601String().substring(0, 10),
        'paused': paused,
      };

  static CustomReminder fromJson(Map<String, Object?> j) => CustomReminder(
        id: j['id']! as String,
        patientId: j['patientId']! as String,
        title: j['title']! as String,
        note: j['note'] as String?,
        times: [for (final t in (j['times']! as List)) ((t as List)[0] as int, t[1] as int)],
        repeat: Repeat.values.byName(j['repeat']! as String),
        days: {for (final d in (j['days'] as List?) ?? const []) d as int},
        start: DateTime.parse(j['start']! as String),
        end: j['end'] == null ? null : DateTime.parse(j['end']! as String),
        paused: (j['paused'] as bool?) ?? false,
      );

  /// Why it cannot be saved, or null.
  String? problem() {
    if (title.trim().isEmpty) return 'Say what to remind you of.';
    if (title.length > maxTitle) return 'Keep it under $maxTitle characters.';
    if ((note?.length ?? 0) > maxNote) return 'Keep the note under $maxNote characters.';
    if (times.isEmpty) return 'Add at least one time.';
    if (repeat == Repeat.weekdays && days.isEmpty) return 'Pick at least one day.';
    if (end != null && _date(end!).isBefore(_date(start))) return 'The end date is before the start.';
    return null;
  }
}
