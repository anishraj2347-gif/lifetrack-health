import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/insight.dart';
import '../theme.dart';
import 'parts.dart';

/// Renders an [Insight] exactly as Plane A emitted it. Styling follows
/// severity; wording is never changed here.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight});
  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final flood = i.severity == Severity.contactDoctorToday || i.severity == Severity.urgentCare;
    final (label, icon) = switch (i.severity) {
      Severity.note => ('For your next visit', LucideIcons.info),
      Severity.discussSoon => ('Discuss at your next visit', LucideIcons.stethoscope),
      Severity.contactDoctorToday => ('Contact your doctor today', LucideIcons.phone),
      Severity.urgentCare => ('Seek care now', LucideIcons.siren),
    };
    final fg = flood ? Colors.white : LT.ink;
    return ShadCard(
      color: flood ? LT.signal : LT.ground,
      borderColor: flood ? LT.signal : (i.severity == Severity.discussSoon ? const Color(0xFFFED7AA) : LT.rule),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: flood ? Colors.white : (i.severity == Severity.discussSoon ? LT.signal : LT.ink3)),
          const SizedBox(width: 8),
          Flexible(
            child: flood
                ? Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))
                : Badge2(label, tone: i.severity == Severity.discussSoon ? BadgeTone.signal : BadgeTone.neutral),
          ),
        ]),
        const SizedBox(height: 10),
        Text(i.finding, style: TextStyle(fontFamily: LT.body, fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: fg)),
        const SizedBox(height: 8),
        Text(i.action, style: TextStyle(fontFamily: LT.body, fontSize: 13.5, height: 1.5, color: flood ? Colors.white : LT.ink3)),
      ]),
    );
  }
}
