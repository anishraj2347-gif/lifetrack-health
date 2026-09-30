import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
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

  static String timingLabel(String? timing) => switch (timing) {
        'before_food' => t('Before food'),
        'after_food' => t('After food'),
        'with_food' => t('With food'),
        _ => t('Any time'),
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
          const IconTile(LucideIcons.pill, color: LT.ink, background: LT.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: LT.onDark)),
              if (r.ingredient != null) Text('Contains ${r.ingredient}', style: const TextStyle(fontSize: 12.5, color: LT.onDarkMuted)),
              const SizedBox(height: 8),
              Badge2(
                r.endDate == null
                    ? t('No end date given')
                    : active
                        ? '$left day${left == 1 ? '' : 's'} left'
                        : t('Course finished'),
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
            Text(t('How much, and when'), style: LT.small.copyWith(fontWeight: FontWeight.w600, color: LT.ink2)),
            const SizedBox(height: 12),
            Row(children: [
              _slot(LucideIcons.sunrise, t('Morning'), d.morning),
              const SizedBox(width: 8),
              _slot(LucideIcons.sun, t('Afternoon'), d.afternoon),
              const SizedBox(width: 8),
              _slot(LucideIcons.moon, t('Night'), d.night),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(LucideIcons.utensils, size: 16, color: LT.ink3),
              const SizedBox(width: 8),
              Text(timingLabel(r.timing), style: LT.label.copyWith(fontSize: 14)),
              const Spacer(),
              Text('${d.perDay} a day', style: LT.small),
            ]),
          ]),
        ),

      // How long.
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _row(LucideIcons.calendar, t('Started'), fullDate(r.date)),
          if (r.endDate != null) _row(LucideIcons.calendarCheck, t('Ends'), fullDate(r.endDate!)),
          if (days != null) _row(LucideIcons.clock, t('Course'), '$days days', last: true),
        ]),
      ),

      // The doctor's own words.
      if (r.instructions != null && r.instructions!.trim().isNotEmpty)
        ShadCard(
          color: LT.raised,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(LucideIcons.messageSquareText, size: 18, color: LT.ink2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Doctor\'s instructions'), style: LT.small.copyWith(fontWeight: FontWeight.w600, color: LT.ink2)),
                const SizedBox(height: 4),
                Text(r.instructions!, style: LT.label.copyWith(fontSize: 15, height: 1.5)),
              ]),
            ),
          ]),
        ),

      // Who prescribed it, and how we know.
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (r.doctor != null) _row(LucideIcons.stethoscope, t('Prescribed by'), r.doctor!),
          if (r.prescriberRegistration != null) _row(LucideIcons.badgeCheck, t('Registration'), r.prescriberRegistration!),
          if (r.facility != null) _row(LucideIcons.hospital, t('Clinic'), r.facility!),
          _row(
            LucideIcons.fileCheck,
            t('Source'),
            switch (r.source) {
              RecordSource.doctorIssued => t('Signed by a verified doctor'),
              RecordSource.smartCapture => t('Photo of the prescription'),
              RecordSource.labSigned => t('Delivered by the lab'),
              RecordSource.restoredFromBackup => t('Restored from your backup'),
              RecordSource.typedByPatient => t('Typed in by you'),
            },
            last: true,
          ),
        ]),
      ),
      if (r.patientConfirmedAt != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Text('You confirmed you were still taking this on ${fullDate(r.patientConfirmedAt!)}.', style: LT.small),
        ),
    ]);
  }

  Widget _slot(IconData icon, String label, int count) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: count > 0 ? LT.primary : LT.raised,
            borderRadius: BorderRadius.circular(LT.radius),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: count > 0 ? LT.accent : LT.inactive),
            const SizedBox(height: 6),
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: count > 0 ? LT.onDark : LT.inactive)),
            Text(label, style: TextStyle(fontSize: 11.5, color: count > 0 ? LT.onDarkMuted : LT.inactive)),
          ]),
        ),
      );

  Widget _row(IconData icon, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: LT.rule))),
        child: Row(children: [
          Icon(icon, size: 16, color: LT.ink3),
          const SizedBox(width: 12),
          Text(label, style: LT.small),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: LT.label.copyWith(fontSize: 14), textAlign: TextAlign.right)),
        ]),
      );
}
