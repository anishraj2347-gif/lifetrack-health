import 'package:flutter/material.dart';

import '../../ai/insight.dart';
import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/insight_card.dart';
import '../widgets/parts.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Future<InsightRun?>? _run;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run = AppScope.of(context).runInsights();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.insightsEnabled()) return _off(context);
    return FutureBuilder<InsightRun?>(
      future: _run,
      builder: (context, snap) {
        final run = snap.data;
        if (run == null) return const Center(child: CircularProgressIndicator());
        return ListView(children: [
          const Masthead(eyebrow: 'Insights · on this phone', title: 'What your numbers show'),
          const Note(Insight.disclaimer),
          const SizedBox(height: 14),
          for (final i in run.insights) InsightCard(insight: i),
          if (run.unresolved.isNotEmpty) ...[
            const Eyebrow('Not checked'),
            CautionPanel(
              title: '${run.unresolved.length} result${run.unresolved.length == 1 ? '' : 's'} could not be compared',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final u in run.unresolved)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${analyteName(u.analyte)} ${u.value} ${u.unit} — ${u.explanation}', style: LT.small.copyWith(color: LT.ink)),
                  ),
                const SizedBox(height: 8),
                Text('Not being able to check a result says nothing about whether it is fine. Ask your doctor about these.', style: LT.small.copyWith(color: LT.ink, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          if (run.insights.isEmpty && run.allChecked)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text('Every result LifeTrack could compare was inside its published range. Your doctor may still want to discuss them.', style: LT.lede),
            ),
          const Eyebrow('Deeper analysis'),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: LT.rule, width: 1.5)),
            child: Text(
              s.cloud.isAvailable(s.clock())
                  ? 'Available.'
                  : 'Not available in this version. Longer-term pattern analysis needs regulatory certification before it can be offered, and it would send a de-identified summary off this phone — only after you read exactly what leaves and tap to confirm.',
              style: LT.small,
            ),
          ),
        ]);
      },
    );
  }

  Widget _off(BuildContext context) => ListView(children: [
        const Masthead(eyebrow: 'Insights', title: 'Compare with published ranges'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'LifeTrack can compare your report values with published reference ranges, notice when a value moves between reports, and spot two prescriptions for the same medicine. It runs on this phone.',
            style: LT.lede,
          ),
        ),
        const Note('Turning this on gives the on-device insights feature permission to read your reports and prescriptions for 24 hours. Every read appears in your access log. You can turn it off from Share at any time.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: SlabButton('Turn on for 24 hours', onPressed: () async {
            await AppScope.of(context).enableInsights();
            if (!context.mounted) return;
            final next = AppScope.of(context).runInsights();
            setState(() {
              _run = next;
            });
            AppScope.changed(context);
          }),
        ),
      ]);
}
