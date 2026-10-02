import 'package:lifetrack/src/ai/plane_b/capture.dart';

/// A page as the reader returns it: one reader line per string, words laid
/// left to right, rows 40 px apart. [columns] splits each row into reader
/// lines at ' | ', the way Tesseract splits a table into column blocks.
OcrPage page(List<String> rows, {double conf = 93, int dy = 0}) {
  final words = <OcrWord>[];
  var line = 0;
  for (final (r, row) in rows.indexed) {
    var x = 40;
    for (final cell in row.split(' | ')) {
      line++;
      for (final t in cell.split(' ').where((t) => t.isNotEmpty)) {
        // dy tilts the page: each word drops a little further right.
        final top = 100 + r * 40 + (x * dy) ~/ 1000;
        words.add(OcrWord(t, confidence: conf, left: x, top: top, right: x + t.length * 12, bottom: top + 22, line: line));
        x += t.length * 12 + 10;
      }
      x += 120;
    }
  }
  // The reader hands back column blocks, not rows.
  words.sort((a, b) => a.line.compareTo(b.line));
  return OcrPage(words);
}
