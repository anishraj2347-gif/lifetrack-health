import 'dart:io';

/// Every Dart file under [dir], relative to the app root.
List<File> dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Source with comments removed. Every source-scanning invariant must use
/// this: a comment explaining why a capability is absent, or quoting a
/// withdrawn claim, would otherwise trip the scan. That has bitten four times.
String codeOf(File f) {
  final src = f.readAsStringSync().replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return src.split('\n').map((l) {
    final t = l.trimLeft();
    if (t.startsWith('//')) return '';
    // Trailing `// ...` outside a string: good enough for this codebase,
    // which never puts `//` inside a string literal on a code line.
    final i = l.indexOf(' // ');
    return i >= 0 && !l.substring(0, i).contains("'") ? l.substring(0, i) : l;
  }).join('\n');
}

/// The contents of every string literal in [code], with adjacent literals
/// (implicit concatenation) joined by a space.
String stringsOf(String code) {
  final out = StringBuffer();
  var i = 0;
  while (i < code.length) {
    final q = code[i];
    if (q != "'" && q != '"') {
      i++;
      continue;
    }
    final triple = code.startsWith(q * 3, i);
    final end = triple ? q * 3 : q;
    i += end.length;
    while (i < code.length && !code.startsWith(end, i)) {
      if (code[i] == '\\' && i + 1 < code.length) {
        out.write(code[i + 1]);
        i += 2;
        continue;
      }
      out.write(code[i]);
      i++;
    }
    i += end.length;
    out.write(' ');
  }
  return out.toString();
}
