import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/insight.dart';
import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../theme.dart';
import 'insight_card.dart';
import 'parts.dart';

/// What the danger-level check found, shown right after a save, in place of
/// any "saved" celebration. Renders the Insights as they were emitted (#8)
/// and cannot be tapped away by accident.
Future<void> showCriticalPrompt(BuildContext context, InsightRun run) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => _CriticalPrompt(run: run, onDone: () => Navigator.of(c).pop()),
    );

class _CriticalPrompt extends StatelessWidget {
  const _CriticalPrompt({required this.run, required this.onDone});
  final InsightRun run;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final urgent = run.insights.any((i) => i.severity == Severity.urgentCare);
    return Dialog(
      insetPadding: EdgeInsets.all(14),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.symmetric(vertical: 18), children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(run.insights.isEmpty ? 'Saved, but not checked' : 'Saved. Please read this now', style: LT.title.copyWith(fontSize: 20)),
        ),
        for (final i in run.insights) InsightCard(insight: i),
        if (run.unresolved.isNotEmpty)
          CautionPanel(
            title: 'Not checked for danger levels',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final u in run.unresolved)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('${analyteName(u.analyte)} ${u.value} ${u.unit} — ${u.explanation}', style: LT.small.copyWith(color: LT.cautionInk)),
                ),
              SizedBox(height: 8),
              Text('This says nothing about whether the value is fine. Ask your doctor to look at it.', style: LT.small.copyWith(color: LT.cautionInk, fontWeight: FontWeight.w600)),
            ]),
          ),
        if (urgent)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SlabButton('Call 108', icon: LucideIcons.phoneCall, onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await launchUrl(Uri(scheme: 'tel', path: '108'));
              if (!ok) messenger.showSnackBar(SnackBar(content: Text('Could not open the dialer. The number is 108.')));
            }),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SlabButton('I have read this', variant: ButtonVariant.outline, onPressed: onDone),
        ),
      ]),
    );
  }
}
