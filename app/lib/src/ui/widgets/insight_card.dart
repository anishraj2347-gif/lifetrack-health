import 'package:flutter/material.dart';

import '../../ai/insight.dart';
import '../theme.dart';

/// Renders an [Insight] exactly as Plane A emitted it. Styling follows
/// severity; wording is never changed here.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight});
  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final flood = i.severity == Severity.contactDoctorToday || i.severity == Severity.urgentCare;
    final outline = i.severity == Severity.discussSoon;
    final fg = flood ? Colors.white : LT.ink;
    final label = switch (i.severity) {
      Severity.note => 'For your next visit',
      Severity.discussSoon => 'Discuss at your next visit',
      Severity.contactDoctorToday => 'Contact your doctor today',
      Severity.urgentCare => 'Seek care now',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: flood ? LT.signal : null,
        border: Border.all(color: flood || outline ? LT.signal : LT.rule, width: outline ? 2 : 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontFamily: LT.mono, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: flood ? Colors.white : (outline ? LT.signal : LT.ink3)),
        ),
        const SizedBox(height: 8),
        Text(i.finding, style: TextStyle(fontFamily: LT.body, fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: fg)),
        const SizedBox(height: 8),
        Text(i.action, style: TextStyle(fontFamily: LT.body, fontSize: 13.5, height: 1.45, color: flood ? Colors.white : LT.ink2)),
      ]),
    );
  }
}
