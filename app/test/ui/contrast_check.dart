import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every visible text against the nearest solid colour behind it — the
/// widget tree's own colours, not pixels, so a small badge on a black card is
/// judged on that card (Flutter's guideline judges whole semantics nodes and
/// misses it). WCAG AA: 4.5:1, or 3:1 for large text (≥ 18 px, or 14 px bold).
List<String> lowContrastTexts(WidgetTester tester, {Color page = const Color(0xFFE3E3DC)}) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double ratio(Color a, Color b) {
    final (x, y) = (lum(a), lum(b));
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  Color? solid(Color? c) => c == null || c.a < 0.99 ? null : c;

  Color? colourOf(Widget w) => switch (w) {
        Material(:final color, :final type) when type != MaterialType.transparency => solid(color),
        ColoredBox(:final color) => solid(color),
        DecoratedBox(decoration: BoxDecoration(:final color)) => solid(color),
        DecoratedBox(decoration: ShapeDecoration(:final color)) => solid(color),
        Container(:final color) when color != null => solid(color),
        Scaffold(:final backgroundColor) when backgroundColor != null => solid(backgroundColor),
        _ => null,
      };

  final bad = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final rp = e.renderObject;
    if (rp is! RenderParagraph || !rp.attached || !rp.hasSize || rp.size.isEmpty) continue;
    final style = rp.text.style;
    final fg = style?.color;
    final text = rp.text.toPlainText().trim();
    if (fg == null || fg.a < 0.99 || text.isEmpty) continue;
    // Icons are drawn as text glyphs; they are not words to read.
    if (e.findAncestorWidgetOfExactType<Icon>() != null) continue;
    // Material chips paint their own background (not a widget colour this
    // walk can see); their selected and unselected colours come from one theme.
    if (e.findAncestorWidgetOfExactType<RawChip>() != null) continue;
    // Off screen (scrolled away): not seen, not judged.
    final box = rp.localToGlobal(Offset.zero) & rp.size;
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    if (!screen.overlaps(box)) continue;
    Color? bg;
    e.visitAncestorElements((a) {
      bg = colourOf(a.widget);
      return bg == null;
    });
    final size = style?.fontSize ?? 14;
    final bold = (style?.fontWeight?.value ?? 400) >= 700;
    final need = size >= 18 || (size >= 14 && bold) ? 3.0 : 4.5;
    final r = ratio(fg, bg ?? page);
    if (r < need) bad.add('"${text.length > 40 ? '${text.substring(0, 40)}…' : text}" ${r.toStringAsFixed(2)}:1 (needs $need)');
  }
  return bad;
}
