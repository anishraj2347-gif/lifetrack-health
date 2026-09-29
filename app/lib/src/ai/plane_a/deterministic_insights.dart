import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../insight.dart';
import 'banned_phrases.dart';
import 'critical_values.dart';
import 'reference_ranges.dart';

/// Minimum change between two consecutive results that counts as a trend,
/// and which direction is the worse one.
class TrendRule {
  const TrendRule(this.unit, this.threshold, {required this.worseIsUp});
  final String unit;
  final double threshold;
  final bool worseIsUp;
}

const trendRules = <String, TrendRule>{
  'hba1c': TrendRule('%', 0.5, worseIsUp: true),
  'glucose_fasting': TrendRule('mg/dL', 15, worseIsUp: true),
  'ldl': TrendRule('mg/dL', 20, worseIsUp: true),
  'hdl': TrendRule('mg/dL', 8, worseIsUp: false),
  'haemoglobin': TrendRule('g/dL', 1.0, worseIsUp: false),
  'creatinine': TrendRule('mg/dL', 0.3, worseIsUp: true),
};

/// Plane A: deterministic, on-device, Tier 1. Pure — takes records the
/// caller has already obtained through `RecordAccess`, and a clock.
///
/// An unchecked result must never be rendered as reassurance: everything that
/// could not be compared comes back in [InsightRun.unresolved].
abstract final class DeterministicInsights {
  static InsightRun run({required Patient patient, required List<HealthRecord> records, required DateTime at}) {
    final out = <Insight>[];
    final unresolved = <NotChecked>[];
    final byDate = [...records]..sort((a, b) => a.date.compareTo(b.date));

    // Latest result per analyte drives range and critical findings.
    final latest = <String, (HealthRecord, LabResult)>{};
    final series = <String, List<(HealthRecord, LabResult)>>{};
    for (final r in byDate) {
      for (final res in r.results) {
        latest[res.analyte] = (r, res);
        series.putIfAbsent(res.analyte, () => []).add((r, res));
      }
    }

    for (final MapEntry(key: analyte, value: (rec, res)) in latest.entries) {
      final (lookup, range) = referenceRangeFor(analyte, patient, at);
      if (lookup == RangeLookup.noRange) {
        unresolved.add(_nc(rec, res, NotCheckedReason.noRangeForAnalyte));
        continue;
      }
      if (lookup == RangeLookup.notApplicable) {
        unresolved.add(_nc(rec, res, NotCheckedReason.notApplicableToPatient));
        continue;
      }
      if (!range!.matchesUnit(res.unit)) {
        unresolved.add(_nc(rec, res, NotCheckedReason.unitMismatch));
        continue;
      }
      if (range.contains(res.value)) continue;

      final critical = criticalLimits
          .where((c) => c.analyte == analyte && c.unit == range.unit)
          .map((c) => c.classify(res.value))
          .whereType<Severity>()
          .firstOrNull;
      final severity = critical ?? Severity.discussSoon;
      final side = range.isAbove(res.value) ? 'above' : 'below';
      out.add(Insight(
        kind: critical == null ? InsightKind.outOfRange : InsightKind.critical,
        severity: severity,
        analyte: analyte,
        finding: '${analyteName(analyte)} was ${_fmt(res.value)} ${res.unit} on ${_date(rec.date)}. '
            'That is $side the reference range of ${range.describe()} for ${range.population}.',
        action: actionFor(severity),
        evidence: [rec.id],
      ));
    }

    for (final MapEntry(key: analyte, value: points) in series.entries) {
      final rule = trendRules[analyte];
      if (rule == null || points.length < 2) continue;
      final (prevRec, prev) = points[points.length - 2];
      final (lastRec, last) = points.last;
      if (prev.unit != rule.unit || last.unit != rule.unit) continue;
      final delta = last.value - prev.value;
      if (delta.abs() < rule.threshold) continue;
      final worsening = rule.worseIsUp ? delta > 0 : delta < 0;
      final (lookup, range) = referenceRangeFor(analyte, patient, at);
      final endsOutside = lookup == RangeLookup.found &&
          range!.matchesUnit(last.unit) &&
          !range.contains(last.value);
      // Direction- and endpoint-aware: an improving value is never red, and a
      // worsening one is raised only once it has left the range.
      final severity = worsening && endsOutside ? Severity.discussSoon : Severity.note;
      out.add(Insight(
        kind: InsightKind.trend,
        severity: severity,
        analyte: analyte,
        finding: '${analyteName(analyte)} went from ${_fmt(prev.value)} to ${_fmt(last.value)} ${last.unit} '
            'between ${_date(prevRec.date)} and ${_date(lastRec.date)}.',
        action: actionFor(severity),
        evidence: [prevRec.id, lastRec.id],
      ));
    }

    out.addAll(_duplicateIngredients(byDate, at));

    final kept = [for (final i in out) if (firstBannedPhrase('${i.finding} ${i.action}') == null) i];
    kept.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return InsightRun(insights: kept, unresolved: unresolved, dropped: out.length - kept.length);
  }

  /// Two prescriptions for the same ingredient within 90 days.
  static List<Insight> _duplicateIngredients(List<HealthRecord> records, DateTime at) {
    final recent = records.where((r) =>
        r.kind == RecordKind.prescription &&
        r.ingredient != null &&
        at.difference(r.date).inDays <= 90);
    final byIngredient = <String, List<HealthRecord>>{};
    for (final r in recent) {
      byIngredient.putIfAbsent(r.ingredient!, () => []).add(r);
    }
    return [
      for (final MapEntry(key: ing, value: rs) in byIngredient.entries)
        if (rs.map((r) => r.doctor ?? r.title).toSet().length > 1)
          Insight(
            kind: InsightKind.medication,
            severity: Severity.discussSoon,
            finding: '${rs.length} current prescriptions contain $ing: '
                '${rs.map((r) => '${r.title} (${r.doctor ?? 'unknown doctor'})').join(', ')}.',
            action: 'Show both prescriptions to your doctor or pharmacist before your next dose.',
            evidence: [for (final r in rs) r.id],
          ),
    ];
  }

  static NotChecked _nc(HealthRecord r, LabResult res, NotCheckedReason why) =>
      NotChecked(recordId: r.id, analyte: res.analyte, value: res.value, unit: res.unit, reason: why);

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}
