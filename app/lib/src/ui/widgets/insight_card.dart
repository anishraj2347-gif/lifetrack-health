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
    // Badge words are the app's own (not Plane A's): short, so they do not
    // repeat the action sentence below them.
    final (label, icon) = switch (i.severity) {
      Severity.note => ('Good to know', LucideIcons.info),
      Severity.discussSoon => ('Next visit', LucideIcons.stethoscope),
      Severity.contactDoctorToday => ('Contact your doctor today', LucideIcons.phone),
      Severity.urgentCare => ('Seek care now', LucideIcons.siren),
    };
    if (flood) {
      // The one place a signal flood is earned: solid orange, white text.
      return ShadCard(
        color: LT.signalFill,
        borderColor: LT.signalFill,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
          ]),
          SizedBox(height: 10),
          Text(i.finding, style: TextStyle(fontFamily: LT.body, fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: Colors.white)),
          SizedBox(height: 8),
          Text(i.action, style: TextStyle(fontFamily: LT.body, fontSize: 14, height: 1.5, color: Colors.white)),
        ]),
      );
    }
    final discuss = i.severity == Severity.discussSoon;
    // Glass like every other card; severity is a slim bar at the leading edge
    // plus the badge word — never colour alone.
    return ShadCard(
      padding: EdgeInsets.fromLTRB(12, 16, 16, 16),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, decoration: BoxDecoration(color: discuss ? LT.signal : LT.rule, borderRadius: BorderRadius.circular(2))),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: discuss ? LT.signal : LT.ink3),
                SizedBox(width: 8),
                Flexible(child: Badge2(label, tone: discuss ? BadgeTone.signal : BadgeTone.neutral)),
              ]),
              SizedBox(height: 10),
              Text(i.finding, style: TextStyle(fontFamily: LT.body, fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: LT.ink)),
              SizedBox(height: 8),
              Text(i.action, style: TextStyle(fontFamily: LT.body, fontSize: 14, height: 1.5, color: LT.ink2)),
            ]),
          ),
        ]),
      ),
    );
  }
}
