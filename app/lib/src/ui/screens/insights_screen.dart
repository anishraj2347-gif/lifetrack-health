import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
        final flagged = run.insights.where((i) => i.severity != Severity.note).length;
        return ListView(children: [
          Masthead(eyebrow: t('Insights · runs on this phone'), title: t('What your numbers show')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(children: [
              Expanded(child: _Stat(value: '$flagged', label: t('To discuss with your doctor'), dark: true)),
              const SizedBox(width: 10),
              Expanded(child: _Stat(value: '${run.unresolved.length}', label: t('Could not be checked'))),
            ]),
          ),
          const Note(Insight.disclaimer, margin: EdgeInsets.fromLTRB(16, 6, 16, 4)),
          if (run.insights.isNotEmpty) Eyebrow(t('Findings')),
          for (final i in run.insights) InsightCard(insight: i),
          if (run.unresolved.isNotEmpty) ...[
            Eyebrow(t('Not checked')),
            CautionPanel(
              title: '${run.unresolved.length} result${run.unresolved.length == 1 ? '' : 's'} could not be compared',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final u in run.unresolved)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${analyteName(u.analyte)} ${u.value} ${u.unit} — ${u.explanation}', style: LT.small.copyWith(color: LT.cautionInk)),
                  ),
                const SizedBox(height: 8),
                Text(t('Not being able to check a result says nothing about whether it is fine. Ask your doctor about these.'), style: LT.small.copyWith(color: LT.cautionInk, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          if (run.insights.isEmpty && run.allChecked)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(t('Every result LifeTrack could compare was inside its published range. Your doctor may still want to discuss them.'), style: LT.lede),
            ),
          Eyebrow(t('Deeper analysis')),
          ShadCard(
            margin: EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(LucideIcons.lock, color: LT.ink3),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(t('Long-term patterns'), style: LT.label),
                    Badge2(s.cloud.isAvailable(s.clock()) ? t('Available') : t('Not available yet'), tone: BadgeTone.outline),
                  ]),
                  SizedBox(height: 4),
                  Text(
                    t('Needs regulatory certification first. It would send a de-identified summary off this phone — only after you read exactly what leaves and tap to confirm.'),
                    style: LT.small,
                  ),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _off(BuildContext context) => ListView(children: [
        Masthead(eyebrow: t('Insights'), title: t('Compare with published ranges')),
        SizedBox(height: 8),
        for (final (icon, title, body) in [
          (LucideIcons.chartColumn, t('Out-of-range values'), t('Each report value compared with a published reference range for your age and sex.')),
          (LucideIcons.trendingUp, t('Changes between reports'), t('Notices when a value moves meaningfully from one report to the next.')),
          (LucideIcons.pill, t('Duplicate medicines'), t('Spots two prescriptions for the same ingredient under different brand names.')),
        ])
          ShadCard(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: LT.label),
                  const SizedBox(height: 4),
                  Text(body, style: LT.small),
                ]),
              ),
            ]),
          ),
        Note(t('Turning this on lets the on-device insights feature read your reports and prescriptions for 24 hours. Every read appears in your access log, and you can turn it off from Share at any time.'), icon: LucideIcons.shieldCheck, margin: EdgeInsets.fromLTRB(16, 16, 16, 0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(t('Turn on for 24 hours'), icon: LucideIcons.activity, onPressed: () async {
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.dark = false});
  final String value;
  final String label;
  final bool dark;
  @override
  Widget build(BuildContext context) => ShadCard(
        margin: EdgeInsets.zero,
        color: dark ? LT.primary : LT.surface,
        child: SizedBox(
          height: 96,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: LT.small.copyWith(color: dark ? LT.onDarkMuted : LT.ink3), maxLines: 2),
            const Spacer(),
            Text(value, style: LT.hero.copyWith(fontSize: 34, color: dark ? LT.onDark : LT.ink)),
          ]),
        ),
      );
}
