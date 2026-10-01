import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ai/plane_a/reference_ranges.dart' show analyteName;
import '../../model/health_record.dart';
import '../theme.dart';
import 'parts.dart';

/// Black hero card: one analyte the patient has measured repeatedly, drawn
/// as dot-matrix columns — one column per report, oldest to newest.
///
/// Deliberately says nothing about whether any value is good or bad: no
/// range, no colour by value (CLAUDE.md #8). Lime marks only the latest
/// column — "now" — which is the one meaning lime has in this app.
class TrendCard extends StatelessWidget {
  const TrendCard({super.key, required this.series, this.onTap, this.maxColumns = 7});

  /// One analyte in one unit, oldest first.
  final TrendSeries series;
  final VoidCallback? onTap;
  final int maxColumns;

  String get analyte => series.analyte;

  /// The minimum number of results before a test gets a trend: more than two.
  static const minResults = 3;

  /// Every test with at least [min] results in one unit, the most recently
  /// measured first.
  static List<TrendSeries> all(List<HealthRecord> records, {int min = minResults}) {
    final by = <String, List<(HealthRecord, LabResult)>>{};
    for (final r in records) {
      for (final res in r.results) {
        by.putIfAbsent('${res.analyte}|${res.unit}', () => []).add((r, res));
      }
    }
    final out = [
      for (final e in by.entries)
        if (e.value.length >= min)
          TrendSeries(e.key.split('|').first, e.key.split('|').last, e.value..sort((a, b) => a.$1.effectiveDate.compareTo(b.$1.effectiveDate))),
    ]..sort((a, b) => b.points.last.$1.effectiveDate.compareTo(a.points.last.$1.effectiveDate));
    return out;
  }

  static const _rows = 6;

  @override
  Widget build(BuildContext context) {
    final all = [for (final (r, x) in series.points) (r.effectiveDate, x.value, x.unit)];
    final points = all.length > maxColumns ? all.sublist(all.length - maxColumns) : all;
    final values = [for (final p in points) p.$2];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final latest = points.last;
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    return ShadCard(
      color: LT.primary,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: LT.accent, shape: BoxShape.circle),
            child: const Icon(LucideIcons.flaskConical, size: 17, color: LT.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your results over time', style: TextStyle(fontSize: 11.5, color: LT.onDarkMuted)),
              Text(analyteName(analyte), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
            ]),
          ),
          if (onTap != null) const Icon(LucideIcons.chevronRight, color: LT.onDarkMuted),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(fmt(latest.$2), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600, color: LT.onDark, letterSpacing: -1.2, height: 1)),
          const SizedBox(width: 6),
          Text(latest.$3, style: const TextStyle(fontSize: 14, color: LT.onDarkMuted)),
        ]),
        const SizedBox(height: 4),
        Text('${all.length} results · ${fullDate(all.first.$1)} – ${fullDate(latest.$1)}${onTap != null ? ' · tap for every result' : ''}', style: const TextStyle(fontSize: 11.5, color: LT.onDarkMuted)),
        const SizedBox(height: 18),
        SizedBox(
          height: _rows * 14.0 + 22,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, p) in points.indexed)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (var r = _rows - 1; r >= 0; r--)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _dot(
                        filled: r < _level(p.$2, lo, hi),
                        now: i == points.length - 1,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(shortMonth(p.$1), style: const TextStyle(fontSize: 10, color: LT.onDarkMuted)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  /// Rows lit for a value: at least one, scaled across this patient's own
  /// min–max. Height is relative to their other results, not to any range.
  static int _level(double v, double lo, double hi) =>
      hi == lo ? _rows ~/ 2 : 1 + ((v - lo) / (hi - lo) * (_rows - 1)).round();

  Widget _dot({required bool filled, required bool now}) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? (now ? LT.accent : LT.onDark) : const Color(0xFF2A2A28),
        ),
      );
}

/// One test in one unit: (record, result), oldest first.
class TrendSeries {
  const TrendSeries(this.analyte, this.unit, this.points);
  final String analyte;
  final String unit;
  final List<(HealthRecord, LabResult)> points;
}
