import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
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
  const TrendCard({super.key, required this.analyte, required this.points});

  final String analyte;

  /// (date, value, unit), oldest first, all in one unit.
  final List<(DateTime, double, String)> points;

  /// The analyte with the most results in a single unit, if any has ≥ 2.
  static TrendCard? pick(List<HealthRecord> records) {
    final series = <String, List<(DateTime, double, String)>>{};
    for (final r in records) {
      for (final res in r.results) {
        series.putIfAbsent('${res.analyte}|${res.unit}', () => []).add((r.date, res.value, res.unit));
      }
    }
    final best = series.entries.where((e) => e.value.length >= 2).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (best.isEmpty) return null;
    final pts = best.first.value..sort((a, b) => a.$1.compareTo(b.$1));
    return TrendCard(analyte: best.first.key.split('|').first, points: pts.length > 7 ? pts.sublist(pts.length - 7) : pts);
  }

  static const _rows = 6;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) p.$2];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final latest = points.last;
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    return ShadCard(
      color: LT.primary,
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
              Text(t('Your results over time'), style: TextStyle(fontSize: 11.5, color: LT.onDarkMuted)),
              Text(analyteName(analyte), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(fmt(latest.$2), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600, color: LT.onDark, letterSpacing: -1.2, height: 1)),
          const SizedBox(width: 6),
          Text(latest.$3, style: const TextStyle(fontSize: 14, color: LT.onDarkMuted)),
        ]),
        const SizedBox(height: 4),
        Text('${points.length} reports · ${fullDate(points.first.$1)} – ${fullDate(latest.$1)}', style: const TextStyle(fontSize: 11.5, color: LT.onDarkMuted)),
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
