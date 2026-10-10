import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/health_record.dart';
import '../theme.dart';
import 'parts.dart';

/// A prescription as the patient needs it at home: what, how much, when,
/// for how long, and the doctor's own words — reproduced exactly, never
/// reworded or judged by the app.
class PrescriptionCard extends StatelessWidget {
  const PrescriptionCard({super.key, required this.record, required this.now});
  final HealthRecord record;
  final DateTime now;

  static String timingLabel(String? t) => switch (t) {
        'before_food' => 'Before food',
        'after_food' => 'After food',
        'with_food' => 'With food',
        _ => 'Any time',
      };

  @override
  Widget build(BuildContext context) {
    final r = record;
    final d = r.dose;
    final active = r.isActiveAt(now);
    final days = r.endDate?.difference(r.date).inDays;
    final left = r.endDate?.difference(now).inDays;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // What and status.
      ShadCard(
        color: LT.primary,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(LucideIcons.pill, color: LT.onDark, background: LT.onDarkChip),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: LT.onDark)),
              if (r.ingredient != null) Text('Contains ${r.ingredient}', style: TextStyle(fontSize: 14, color: LT.onDarkMuted)),
              SizedBox(height: 8),
              Badge2(
                r.endDate == null
                    ? 'No end date given'
                    : active
                        ? '$left day${left == 1 ? '' : 's'} left'
                        : 'Course finished',
                tone: active ? BadgeTone.trace : BadgeTone.outline,
              ),
            ]),
          ),
        ]),
      ),

      // When to take it.
      if (d != null)
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How much, and when', style: LT.small.copyWith(fontWeight: FontWeight.w600, color: LT.ink2)),
            SizedBox(height: 12),
            Row(children: [
              _slot(LucideIcons.sunrise, 'Morning', d.morning),
              SizedBox(width: 8),
              _slot(LucideIcons.sun, 'Afternoon', d.afternoon),
              SizedBox(width: 8),
              _slot(LucideIcons.moon, 'Night', d.night),
            ]),
            SizedBox(height: 16),
            Row(children: [
              Icon(LucideIcons.utensils, size: 16, color: LT.ink3),
              SizedBox(width: 8),
              Text(timingLabel(r.timing), style: LT.label.copyWith(fontSize: 14)),
              Spacer(),
              Text('${d.perDay} a day', style: LT.small),
            ]),
          ]),
        ),

      // How long.
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _row(LucideIcons.calendar, 'Started', fullDate(r.date)),
          if (r.endDate != null) _row(LucideIcons.calendarCheck, 'Ends', fullDate(r.endDate!)),
          if (days != null) _row(LucideIcons.clock, 'Course', '$days days', last: true),
        ]),
      ),

      // The doctor's own words.
      if (r.instructions != null && r.instructions!.trim().isNotEmpty)
        ShadCard(
          color: LT.raised,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.messageSquareText, size: 18, color: LT.ink2),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Doctor's instructions", style: LT.small.copyWith(fontWeight: FontWeight.w600, color: LT.ink2)),
                SizedBox(height: 4),
                Text(r.instructions!, style: LT.label.copyWith(fontSize: 15, height: 1.5)),
              ]),
            ),
          ]),
        ),

      // Who prescribed it, and how we know.
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (r.doctor != null) _row(LucideIcons.stethoscope, 'Prescribed by', r.doctor!),
          if (r.prescriberRegistration != null) _row(LucideIcons.badgeCheck, 'Registration', r.prescriberRegistration!),
          if (r.facility != null) _row(LucideIcons.hospital, 'Clinic', r.facility!),
          _row(
            LucideIcons.fileCheck,
            'Source',
            switch (r.source) {
              RecordSource.doctorIssued => 'Signed by a verified doctor',
              RecordSource.smartCapture => 'Photo of the prescription',
              RecordSource.labSigned => 'Delivered by the lab',
              RecordSource.restoredFromBackup => 'Restored from your backup',
              RecordSource.typedByPatient => 'Typed in by you',
            },
            last: true,
          ),
        ]),
      ),
      if (r.patientConfirmedAt != null)
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Text('You confirmed you were still taking this on ${fullDate(r.patientConfirmedAt!)}.', style: LT.small),
        ),
    ]);
  }

  Widget _slot(IconData icon, String label, int count) => Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: count > 0 ? LT.primary : LT.raised,
            borderRadius: BorderRadius.circular(LT.radius),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: count > 0 ? LT.accent : LT.inactive),
            SizedBox(height: 6),
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: count > 0 ? LT.onDark : LT.ink3)),
            Text(label, style: TextStyle(fontSize: 12, color: count > 0 ? LT.onDarkMuted : LT.ink3)),
          ]),
        ),
      );

  Widget _row(IconData icon, String label, String value, {bool last = false}) => Container(
        padding: EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: LT.rule))),
        child: Row(children: [
          Icon(icon, size: 16, color: LT.ink3),
          SizedBox(width: 12),
          Text(label, style: LT.small),
          SizedBox(width: 12),
          Expanded(child: Text(value, style: LT.label.copyWith(fontSize: 14), textAlign: TextAlign.right)),
        ]),
      );
}
