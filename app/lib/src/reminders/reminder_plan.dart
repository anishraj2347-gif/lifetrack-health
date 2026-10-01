import '../model/health_record.dart';
import '../model/patient.dart';

enum DoseSlot {
  morning('Morning'),
  afternoon('Afternoon'),
  night('Night');

  const DoseSlot(this.label);
  final String label;

  int countIn(Dose d) => switch (this) { morning => d.morning, afternoon => d.afternoon, night => d.night };
}

/// The patient's choices. Off until they turn it on; names hidden on the
/// lock screen unless they choose otherwise.
class ReminderSettings {
  const ReminderSettings({this.on = false, this.showNames = false, this.times = defaultTimes});

  static const defaultTimes = {DoseSlot.morning: (8, 0), DoseSlot.afternoon: (14, 0), DoseSlot.night: (21, 0)};

  final bool on;
  final bool showNames;
  final Map<DoseSlot, (int, int)> times;

  ReminderSettings copyWith({bool? on, bool? showNames, Map<DoseSlot, (int, int)>? times}) =>
      ReminderSettings(on: on ?? this.on, showNames: showNames ?? this.showNames, times: times ?? this.times);

  Map<String, Object?> toJson() => {
        'on': on,
        'showNames': showNames,
        'times': {for (final e in times.entries) e.key.name: [e.value.$1, e.value.$2]},
      };

  static ReminderSettings fromJson(Map<String, Object?> j) => ReminderSettings(
        on: (j['on'] as bool?) ?? false,
        showNames: (j['showNames'] as bool?) ?? false,
        times: {
          ...defaultTimes,
          for (final e in ((j['times'] as Map?) ?? const {}).entries)
            DoseSlot.values.byName(e.key as String): ((e.value as List)[0] as int, (e.value as List)[1] as int),
        },
      );
}

class ReminderItem {
  const ReminderItem({required this.patient, required this.record, required this.count});
  final Patient patient;
  final HealthRecord record;
  final int count;
}

class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.slot, required this.items});
  final int id;
  final DateTime at;
  final DoseSlot slot;
  final List<ReminderItem> items;

  String get title => '${slot.label} medicines';

  /// What the notification says. Without [showNames] it names no medicine
  /// and no person — the lock screen is public.
  String body({required bool showNames, String? selfPatientId}) {
    if (!showNames) return items.length == 1 ? 'Time for 1 medicine. Open LifeTrack to see it.' : 'Time for ${items.length} medicines. Open LifeTrack to see them.';
    final people = items.map((i) => i.patient.id).toSet().length;
    return items
        .map((i) => '${people > 1 ? '${i.patient.id == selfPatientId ? 'You' : i.patient.name.split(' ').first}: ' : ''}${i.record.title}${i.count > 1 ? ' ×${i.count}' : ''}')
        .join(' · ');
  }
}

/// Every reminder for the next [days] days, from each active prescription's
/// dose. Computed afresh whenever records change, so a course that ends, or
/// a medicine that is deleted, stops being reminded without the app needing
/// to be open on the day.
List<PlannedReminder> planReminders({
  required List<(Patient, List<HealthRecord>)> people,
  required ReminderSettings settings,
  required DateTime now,
  int days = 14,
}) {
  final out = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);
  for (var d = 0; d < days; d++) {
    for (final slot in DoseSlot.values) {
      final (h, m) = settings.times[slot]!;
      final at = DateTime(today.year, today.month, today.day + d, h, m);
      if (!at.isAfter(now)) continue;
      final items = [
        for (final (p, records) in people)
          for (final r in records)
            if (r.kind == RecordKind.prescription && r.dose != null && r.isActiveAt(at) && !r.date.isAfter(at) && slot.countIn(r.dose!) > 0)
              ReminderItem(patient: p, record: r, count: slot.countIn(r.dose!)),
      ];
      if (items.isNotEmpty) out.add(PlannedReminder(id: d * 3 + slot.index, at: at, slot: slot, items: items));
    }
  }
  return out;
}

/// Puts a plan on the phone. The app uses local notifications; tests use a
/// list.
abstract interface class ReminderScheduler {
  Future<bool> requestPermission();
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool showNames, String? selfPatientId});
}

class RecordingScheduler implements ReminderScheduler {
  List<PlannedReminder> scheduled = const [];
  bool permission = true;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool showNames, String? selfPatientId}) async => scheduled = plan;
}
