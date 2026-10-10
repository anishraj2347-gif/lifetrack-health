import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// column — "now" — or the column the patient is touching ("selected"):
/// the two meanings lime has in this app. Touch or drag along the dots to
/// read each result and its date.
class TrendCard extends StatefulWidget {
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

  /// Rows lit for a value: at least one. The scale starts at 80% of this
  /// patient's lowest result, so a small change draws as a small change.
  /// Height is relative to their own results, never to a range.
  static int _level(double v, double lo, double hi) {
    final base = lo > 0 ? lo * 0.8 : lo;
    return hi == base ? _rows ~/ 2 : 1 + ((v - base) / (hi - base) * (_rows - 1)).round();
  }

  @override
  State<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<TrendCard> {
  /// The column being read; null shows the latest.
  int? _picked;

  TrendSeries get series => widget.series;
  String get analyte => widget.analyte;
  VoidCallback? get onTap => widget.onTap;
  static const _rows = TrendCard._rows;

  @override
  void didUpdateWidget(TrendCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.series, widget.series)) _picked = null;
  }

  void _pick(double dx, double width, int n) {
    final i = (dx / width * n).floor().clamp(0, n - 1);
    if (i != _picked) {
      HapticFeedback.selectionClick();
      setState(() => _picked = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxColumns = widget.maxColumns;
    final all = [for (final (r, x) in series.points) (r.effectiveDate, x.value, x.unit)];
    final points = all.length > maxColumns ? all.sublist(all.length - maxColumns) : all;
    final values = [for (final p in points) p.$2];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
        final sel = _picked == null || _picked! >= points.length ? points.length - 1 : _picked!;
    final shown = points[sel];
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    return ShadCard(
      color: LT.primary,
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: LT.accent, shape: BoxShape.circle),
            child: Icon(LucideIcons.flaskConical, size: 17, color: LT.onAccent),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your results over time', style: TextStyle(fontSize: 11.5, color: LT.onDarkMuted)),
              Text(analyteName(analyte), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
            ]),
          ),
          if (onTap != null) Icon(LucideIcons.chevronRight, color: LT.onDarkMuted),
        ]),
        SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          // The number rolls to the value under the finger.
          TweenAnimationBuilder<double>(
            tween: Tween(end: shown.$2),
            duration: Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              fmt(shown.$2 == shown.$2.roundToDouble() ? v.roundToDouble() : double.parse(v.toStringAsFixed(1))),
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w600, color: LT.onDark, letterSpacing: -1.2, height: 1),
            ),
          ),
          SizedBox(width: 6),
          Text(shown.$3, style: TextStyle(fontSize: 14, color: LT.onDarkMuted)),
          SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 180),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
              child: Text(
                sel == points.length - 1 ? 'Latest · ${fullDate(shown.$1)}' : fullDate(shown.$1),
                key: ValueKey(sel),
                textAlign: TextAlign.right,
                maxLines: 2,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: LT.onDark),
              ),
            ),
          ),
        ]),
        SizedBox(height: 4),
        Text('${all.length} results since ${monthYear(all.first.$1)} · touch the dots to read each${onTap != null ? ', tap the card for all' : ''}', style: TextStyle(fontSize: 12, color: LT.onDarkMuted)),
        SizedBox(height: 18),
        Semantics(
          label: '${analyteName(analyte)}: ${[for (final p in points) '${fmt(p.$2)} in ${shortMonth(p.$1)} ${p.$1.year}'].join(', ')}',
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth, points.length),
              onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth, points.length),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, box.maxWidth, points.length),
              child: SizedBox(
                height: _rows * 14.0 + 24,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final (i, p) in points.indexed)
                    Expanded(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 180),
                        padding: EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: i == sel ? LT.onDarkChip.withValues(alpha: 0.35) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          for (var r = _rows - 1; r >= 0; r--)
                            Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: _dot(
                                filled: r < TrendCard._level(p.$2, lo, hi),
                                now: i == sel,
                                delay: i * 40 + (_rows - r) * 15,
                              ),
                            ),
                          SizedBox(height: 6),
                          Text(shortMonth(p.$1), style: TextStyle(fontSize: 11, fontWeight: i == sel ? FontWeight.w600 : FontWeight.w400, color: i == sel ? LT.onDark : LT.onDarkMuted)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Dots light up column by column the first time the card is drawn.
  Widget _dot({required bool filled, required bool now, required int delay}) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 260 + delay),
        curve: Interval(delay / (260 + delay), 1, curve: Curves.easeOut),
        builder: (context, t, child) => Transform.scale(scale: filled ? 0.6 + 0.4 * t : 1, child: child),
        child: _plainDot(filled: filled, now: now),
      );

  Widget _plainDot({required bool filled, required bool now}) => AnimatedContainer(
        duration: Duration(milliseconds: 180),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? (now ? LT.accent : LT.onDark) : LT.onDarkChip,
        ),
      );
}

/// One test in one unit: (record, result), oldest first.
class TrendSeries {
  TrendSeries(this.analyte, this.unit, this.points);
  final String analyte;
  final String unit;
  final List<(HealthRecord, LabResult)> points;
}
