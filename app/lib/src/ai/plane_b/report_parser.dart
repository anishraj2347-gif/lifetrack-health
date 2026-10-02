import 'dart:math';

import '../../model/health_record.dart';
import 'capture.dart';

/// Turns the words read off a document into a [CaptureDraft].
///
/// Deterministic and on the phone. It only ever fills fields; it never
/// judges a value — a draft states what is printed, and the patient checks
/// it. When unsure it says so through a low confidence, never by guessing
/// harder. [today] bounds dates (no clock here: CLAUDE.md, plane rules).
CaptureDraft parseCapture(List<OcrPage> pages, {required DateTime today}) {
  final lines = [for (final p in pages) ...linesOf(p)];
  if (lines.isEmpty) return CaptureDraft.empty;
  final words = [for (final p in pages) ...p.words];
  final meanConf = words.isEmpty ? 0.0 : words.map((w) => w.confidence).reduce((a, b) => a + b) / words.length;
  // Tesseract reads print; on handwriting its confidence collapses. Then
  // every field waits for the patient's tick.
  final handwriting = meanConf < 60 || (words.length < 25 && meanConf < 70);

  final results = _results(lines);
  final medicines = _medicines(lines);
  final kind = _kind(lines, results.length, medicines.length);
  final date = _date(lines, kind.value!, today);
  var draft = CaptureDraft(
    kind: kind,
    title: _title(lines, kind.value!, results),
    date: date,
    place: _place(lines, kind.value!),
    doctor: _doctor(lines, kind.value!),
    results: kind.value == RecordKind.report ? results : const [],
    medicines: kind.value == RecordKind.prescription ? medicines : const [],
    handwriting: handwriting,
  );
  if (handwriting) {
    draft = CaptureDraft(
      kind: draft.kind.capped(0.5),
      title: draft.title.capped(0.5),
      date: draft.date.capped(0.5),
      place: draft.place.capped(0.5),
      doctor: draft.doctor.capped(0.5),
      results: [for (final r in draft.results) r.capped(0.5)],
      medicines: [for (final m in draft.medicines) m.capped(0.5)],
      handwriting: true,
    );
  }
  return draft;
}

// ---- lines -----------------------------------------------------------------

class OcrLine {
  OcrLine(this.words);
  final List<OcrWord> words;
  late final String text = words.map((w) => w.text).join(' ');
  late final String norm = normalize(text);
  double get confidence => words.isEmpty ? 0 : words.map((w) => w.confidence).reduce(min) / 100;
}

/// Lowercase, letters and digits only, single spaces.
String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Rebuilds the rows of the page. The reader splits a table row into one
/// line per column; segments whose facing ends sit at the same height are
/// joined back, comparing neighbouring ends so a tilted photo still works.
List<OcrLine> linesOf(OcrPage page) {
  final byLine = <int, List<OcrWord>>{};
  for (final w in page.words) {
    if (w.text.trim().isEmpty) continue;
    byLine.putIfAbsent(w.line, () => []).add(w);
  }
  final segs = [for (final ws in byLine.values) ws..sort((a, b) => a.left.compareTo(b.left))]..sort((a, b) => a.first.top.compareTo(b.first.top));
  final used = List.filled(segs.length, false);
  bool sameRow(OcrWord a, OcrWord b) => (a.midY - b.midY).abs() < 0.6 * max(max(a.height, b.height), 1);
  final out = <OcrLine>[];
  for (var i = 0; i < segs.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    final row = [...segs[i]];
    while (true) {
      int? best;
      var gap = 1 << 30;
      for (var j = 0; j < segs.length; j++) {
        if (used[j]) continue;
        final s = segs[j];
        if (s.first.left >= row.last.right - 4 && sameRow(row.last, s.first) && s.first.left - row.last.right < gap) {
          best = j;
          gap = s.first.left - row.last.right;
        } else if (s.last.right <= row.first.left + 4 && sameRow(s.last, row.first) && row.first.left - s.last.right < gap) {
          best = j;
          gap = row.first.left - s.last.right;
        }
      }
      if (best == null) break;
      used[best] = true;
      row.addAll(segs[best]);
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    out.add(OcrLine(row));
  }
  return out;
}

// ---- kind ------------------------------------------------------------------

const _formWords = r'tab|tabs|tablet|cap|caps|capsule|syp|syr|syrup|inj|injection|oint|ointment|cream|gel|drop|drops|susp|suspension|inh|inhaler|sachet|powder|lotion';
final _medLine = RegExp('^(?:\\d{1,2}\\s*[.)]?\\s*)?($_formWords)\\b\\.?\\s*(.+)\$', caseSensitive: false);

DraftField<RecordKind> _kind(List<OcrLine> lines, int results, int medicines) {
  bool has(String re) => lines.any((l) => RegExp('\\b(?:$re)\\b').hasMatch(l.norm));
  var rx = medicines * 2.0;
  var report = results * 2.0;
  var scan = 0.0;
  for (final w in ['rx', 'prescription', 'diagnosis', 'advice', 'follow up', 'c o', 'chief complaints?', 'reg no', 'mbbs']) {
    if (has(w)) rx += 1;
  }
  for (final w in ['reference', 'ref range', 'biological', 'test name', 'units?', 'specimen', 'sample', 'collected', 'laboratory', 'pathology', 'investigations?', 'method']) {
    if (has(w)) report += 1;
  }
  for (final w in ['x ray', 'xray', 'mri', 'ct scan', 'hrct', 'ultrasound', 'usg', 'sonography', 'impression', 'findings', 'radiology', 'mammography', 'echocardiography', 'doppler']) {
    if (has(w)) scan += 1.5;
  }
  final scores = {RecordKind.report: report, RecordKind.prescription: rx, RecordKind.scan: scan};
  final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked[0], second = ranked[1];
  if (top.value == 0) return DraftField(RecordKind.report, confidence: 0.3);
  final conf = top.value >= 4 && top.value >= 2 * second.value
      ? 0.95
      : top.value > second.value
          ? 0.75
          : 0.5;
  return DraftField(top.key, confidence: conf);
}

// ---- lab results -------------------------------------------------------------

/// Names labs print, normalised, for each analyte key. Longest match wins,
/// so "hdl cholesterol" is HDL and not total cholesterol.
const analyteAliases = <String, List<String>>{
  'glucose_fasting': ['fasting blood sugar', 'blood sugar fasting', 'fasting blood glucose', 'blood glucose fasting', 'glucose fasting', 'fasting glucose', 'fasting plasma glucose', 'plasma glucose fasting', 'sugar fasting', 'fbs', 'fpg', 'glucose f'],
  'glucose_pp': ['post prandial blood sugar', 'blood sugar post prandial', 'glucose post prandial', 'post prandial glucose', 'postprandial blood sugar', 'blood sugar pp', 'glucose pp', 'ppbs', 'pp blood sugar', 'plasma glucose pp'],
  'glucose_random': ['random blood sugar', 'blood sugar random', 'glucose random', 'random glucose', 'rbs'],
  'hba1c': ['hba1c', 'hb a1c', 'hba 1c', 'glycosylated haemoglobin', 'glycosylated hemoglobin', 'glycated haemoglobin', 'glycated hemoglobin', 'a1c'],
  'total_cholesterol': ['total cholesterol', 'cholesterol total', 'serum cholesterol', 'cholesterol serum', 'cholesterol'],
  'ldl': ['ldl cholesterol', 'cholesterol ldl', 'ldl c', 'ldl direct', 'low density lipoprotein', 'ldl'],
  'hdl': ['hdl cholesterol', 'cholesterol hdl', 'hdl c', 'hdl direct', 'high density lipoprotein', 'hdl'],
  'vldl': ['vldl cholesterol', 'vldl'],
  'triglycerides': ['triglycerides', 'triglyceride', 'serum triglycerides', 'tg'],
  'haemoglobin': ['haemoglobin', 'hemoglobin', 'haemoglobin hb', 'hemoglobin hb', 'hb', 'hgb'],
  'creatinine': ['serum creatinine', 'creatinine serum', 'creatinine', 's creatinine'],
  'tsh': ['thyroid stimulating hormone', 'tsh ultrasensitive', 'ultrasensitive tsh', 'ultra sensitive tsh', 'tsh 3rd generation', 'tsh'],
  'ferritin': ['serum ferritin', 'ferritin'],
  'vitamin_d': ['25 oh vitamin d', '25 hydroxy vitamin d', 'vitamin d total', 'vitamin d 25 hydroxy', 'vitamin d3', 'vitamin d', 'vit d'],
  'vitamin_b12': ['vitamin b12', 'vitamin b 12', 'vit b12', 'cyanocobalamin'],
  'wbc': ['total leucocyte count', 'total leukocyte count', 'total wbc count', 'wbc count', 'white blood cells', 'tlc', 'wbc'],
  'rbc': ['total rbc count', 'rbc count', 'red blood cells', 'rbc'],
  'platelets': ['platelet count', 'platelets', 'plt'],
  'pcv': ['packed cell volume', 'haematocrit', 'hematocrit', 'pcv', 'hct'],
  'esr': ['erythrocyte sedimentation rate', 'esr'],
  'urea': ['blood urea', 'serum urea', 'urea'],
  'bun': ['blood urea nitrogen', 'bun'],
  'uric_acid': ['serum uric acid', 'uric acid'],
  'alt': ['alanine aminotransferase', 'alt sgpt', 'sgpt alt', 'sgpt', 'alt'],
  'ast': ['aspartate aminotransferase', 'ast sgot', 'sgot ast', 'sgot', 'ast'],
  'alp': ['alkaline phosphatase', 'alp'],
  'bilirubin_total': ['bilirubin total', 'total bilirubin', 'serum bilirubin total'],
  'sodium': ['serum sodium', 'sodium'],
  'potassium': ['serum potassium', 'potassium'],
  'calcium': ['serum calcium', 'calcium total', 'total calcium', 'calcium'],
  'free_t3': ['free t3', 'ft3', 'free triiodothyronine'],
  'free_t4': ['free t4', 'ft4', 'free thyroxine'],
  't3': ['total t3', 't3 total', 'triiodothyronine', 't3'],
  't4': ['total t4', 't4 total', 'thyroxine', 't4'],
};

/// Values outside these are a misread (a lost decimal point, a page number),
/// not a result. Only for analytes whose unit is the same across Indian labs.
const _plausible = <String, (double, double)>{
  'glucose_fasting': (10, 1500), 'glucose_pp': (10, 1500), 'glucose_random': (10, 1500),
  'hba1c': (2, 20), 'total_cholesterol': (30, 1200), 'ldl': (5, 900), 'hdl': (3, 250), 'vldl': (1, 500),
  'triglycerides': (10, 6000), 'haemoglobin': (2, 25), 'creatinine': (0.05, 25), 'tsh': (0.001, 500),
  'ferritin': (0.5, 10000), 'vitamin_d': (1, 250), 'vitamin_b12': (20, 5000), 'pcv': (5, 75), 'esr': (0, 160),
  'urea': (2, 400), 'bun': (1, 200), 'uric_acid': (0.5, 25), 'sodium': (90, 190), 'potassium': (1, 10), 'calcium': (3, 20),
};

/// Printed unit (lowercased, spaces removed) → how LifeTrack writes it.
const _units = <String, String>{
  'mg/dl': 'mg/dL', 'mg%': 'mg/dL', 'g/dl': 'g/dL', 'gm/dl': 'g/dL', 'gms/dl': 'g/dL', 'gm%': 'g/dL', 'g%': 'g/dL',
  '%': '%', 'miu/l': 'mIU/L', 'miu/ml': 'mIU/mL', 'µiu/ml': 'µIU/mL', 'uiu/ml': 'µIU/mL', 'μiu/ml': 'µIU/mL', 'ulu/ml': 'µIU/mL',
  'ng/ml': 'ng/mL', 'ng/dl': 'ng/dL', 'pg/ml': 'pg/mL', 'µg/dl': 'µg/dL', 'ug/dl': 'µg/dL', 'mcg/dl': 'µg/dL',
  'mmol/l': 'mmol/L', 'mmol/mol': 'mmol/mol', 'meq/l': 'mEq/L', 'u/l': 'U/L', 'iu/l': 'IU/L', 'fl': 'fL', 'pg': 'pg',
  'mm/hr': 'mm/hr', 'mm/1sthr': 'mm/hr', 'mm/1hr': 'mm/hr', 'cells/cumm': '/cumm', '/cumm': '/cumm', 'cumm': '/cumm', '/mm3': '/mm³',
  'cells/µl': '/µL', '/µl': '/µL', '/ul': '/µL', '10^3/µl': '10³/µL', '10^3/ul': '10³/µL', 'x10^3/µl': '10³/µL', 'x10^3/ul': '10³/µL',
  'thou/mm3': '10³/µL', 'thou/µl': '10³/µL', 'thou/ul': '10³/µL', '10^6/µl': '10⁶/µL', '10^6/ul': '10⁶/µL', 'mill/cumm': 'million/cumm',
  'million/cumm': 'million/cumm', 'lakhs/cumm': 'lakh/cumm', 'lakh/cumm': 'lakh/cumm', 'lakhs/µl': 'lakh/µL',
};

final _number = RegExp(r'^[<>≤≥]?\d{1,3}(?:,\d{2,3})+(?:\.\d+)?$|^[<>≤≥]?\d+(?:[.,]\d+)?$');

double? parseNumber(String raw) {
  // A high/low flag glued to the number: "13.2H", "4.1*".
  var t = raw.trim().replaceAll(RegExp(r'[*:;]+$'), '').replaceAll(RegExp(r'(?<=\d)[HhLl]$'), '');
  if (!_number.hasMatch(t) || RegExp(r'^[<>≤≥]').hasMatch(t)) return null;
  // 1,50,000 (Indian grouping) or 150,000 → thousands; 5,4 → a decimal comma.
  t = RegExp(r',\d{3}$|,\d{2},').hasMatch(t) || RegExp(r'\d,\d{2,3},').hasMatch(t) ? t.replaceAll(',', '') : t.replaceAll(',', '.');
  return double.tryParse(t);
}

List<DraftField<LabResult>> _results(List<OcrLine> lines) {
  final aliases = [
    for (final e in analyteAliases.entries)
      for (final a in e.value) (key: e.key, alias: a),
  ]..sort((a, b) => b.alias.length.compareTo(a.alias.length));
  final found = <String, DraftField<LabResult>>{};
  for (final line in lines) {
    if (RegExp(r'\bratio\b|/\s*hdl|\bnon hdl\b').hasMatch(line.norm) || line.text.contains('/HDL')) continue;
    final body = line.norm.replaceFirst(RegExp(r'^\d{1,2}\s+'), '');
    ({String key, String alias})? hit;
    var fuzzy = false;
    for (final a in aliases) {
      if (body == a.alias || body.startsWith('${a.alias} ')) {
        hit = a;
        break;
      }
    }
    if (hit == null) {
      for (final a in aliases.where((a) => a.alias.length >= 8)) {
        if (body.length >= a.alias.length && _edits(body.substring(0, a.alias.length), a.alias) <= 1 && (body.length == a.alias.length || body[a.alias.length] == ' ')) {
          hit = a;
          fuzzy = true;
          break;
        }
      }
    }
    if (hit == null) continue;
    // Skip the words that make up the name, then read value, unit, range.
    var nameTokens = hit.alias.split(' ').length + (line.norm.length == body.length ? 0 : 1);
    var i = 0;
    while (i < line.words.length && nameTokens > 0) {
      final n = normalize(line.words[i].text);
      nameTokens -= n.isEmpty ? 0 : n.split(' ').length;
      i++;
    }
    final rest = line.words.sublist(i);
    // The first number is the result. "<0.01" cannot be stored as a number:
    // leave the row to the photo rather than take the range as the value.
    final vi = rest.indexWhere((w) => _number.hasMatch(w.text.trim().replaceAll(RegExp(r'[*:;HhLl]+$'), '')));
    if (vi < 0 || parseNumber(rest[vi].text) == null) continue;
    final valueWord = rest[vi];
    final value = parseNumber(valueWord.text)!;
    final after = rest.sublist(vi + 1);
    String? unit;
    for (var k = 0; k < after.length && unit == null; k++) {
      final one = after[k].text.toLowerCase().replaceAll(' ', '');
      final two = k + 1 < after.length ? one + after[k + 1].text.toLowerCase() : null;
      unit = _units[one] ?? _units[one.replaceAll(RegExp(r'[.,;:)]+$'), '')] ?? (two == null ? null : _units[two]);
    }
    final range = _range(after.map((w) => w.text).join(' '));

    var conf = min(line.words.take(i).map((w) => w.confidence).fold(100.0, min), valueWord.confidence) / 100;
    if (fuzzy) conf -= 0.1;
    if (unit == null) conf = min(conf, 0.6);
    final bounds = _plausible[hit.key];
    if (bounds != null && (value < bounds.$1 || value > bounds.$2)) conf = min(conf, 0.3);
    // A dropped decimal point shows as a value ten times the printed range.
    if (range.high != null && value > range.high! * 10) conf = min(conf, 0.6);
    if (range.low != null && range.low! > 0 && value < range.low! / 10) conf = min(conf, 0.6);

    final field = DraftField(
      LabResult(analyte: hit.key, value: value, unit: unit ?? '', printedLow: range.low, printedHigh: range.high),
      confidence: conf.clamp(0, 1).toDouble(),
      seen: line.text,
    );
    final prior = found[hit.key];
    if (prior == null) {
      found[hit.key] = field;
    } else if (prior.value!.value != value) {
      // The same test printed twice with different numbers: ask.
      found[hit.key] = prior.capped(0.5);
    }
  }
  return found.values.toList();
}

({double? low, double? high}) _range(String s) {
  final t = s.replaceAll(RegExp(r'[–—]'), '-');
  final both = RegExp(r'(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)').firstMatch(t);
  if (both != null) {
    final a = double.parse(both.group(1)!), b = double.parse(both.group(2)!);
    if (a <= b) return (low: a, high: b);
  }
  final upper = RegExp(r'(?:<|≤|up\s*to|upto|less\s+than|below)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(t);
  if (upper != null) return (low: null, high: double.parse(upper.group(1)!));
  final lower = RegExp(r'(?:>|≥|more\s+than|above|greater\s+than)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(t);
  if (lower != null) return (low: double.parse(lower.group(1)!), high: null);
  return (low: null, high: null);
}

int _edits(String a, String b) {
  var prev = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(min);
    }
    prev = cur;
  }
  return prev[b.length];
}

// ---- medicines ---------------------------------------------------------------

final _strength = RegExp(r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|µg|g|gm|ml|iu|%)(?![a-z])', caseSensitive: false);

List<DraftMedicine> _medicines(List<OcrLine> lines) {
  final out = <DraftMedicine>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _medLine.firstMatch(lines[i].text.trim());
    if (m == null) continue;
    final rest = m.group(2)!;
    // The name runs up to the end of the strength, or up to the dose.
    final s = _strength.firstMatch(rest);
    final f = _frequency.firstMatch(rest);
    var end = s?.end ?? f?.start ?? rest.length;
    if (f != null && f.start < end) end = f.start;
    final name = rest.substring(0, end).replaceAll(RegExp(r'[\s\-–:,]+$'), '').trim();
    if (normalize(name).length < 3) continue;
    // Dose, timing and days are often on the line below the name.
    final next = i + 1 < lines.length && _medLine.firstMatch(lines[i + 1].text.trim()) == null ? lines[i + 1] : null;
    final instructions = next == null ? rest : '$rest ${next.text}';
    final conf = lines[i].confidence;
    final dose = _dose(instructions, conf);
    final timing = _timing(instructions);
    final days = _days(instructions);
    out.add(DraftMedicine(
      name: DraftField(_titleCase(name), confidence: min(conf, 0.9), seen: lines[i].text),
      dose: dose,
      timing: timing == null ? const DraftField.none() : DraftField(timing, confidence: min(conf, 0.85)),
      days: days == null ? const DraftField.none() : DraftField(days, confidence: min(conf, 0.85)),
    ));
  }
  return out;
}

final _frequency = RegExp(r'\b([0-3](?:/2)?)\s*[-–—]\s*([0-3](?:/2)?)\s*[-–—]\s*([0-3](?:/2)?)\b|\b(od|o\.d|bd|b\.d|bid|tds|t\.d\.s|tid|qid|hs|h\.s|sos|once\s+a\s+day|once\s+daily|twice\s+a\s+day|twice\s+daily|thrice\s+a\s+day|at\s+bed\s*time|at\s+night|morning)\b', caseSensitive: false);

DraftField<Dose> _dose(String s, double conf) {
  final m = _frequency.firstMatch(s);
  if (m == null) return const DraftField.none();
  if (m.group(1) != null) {
    int n(String x) => x.contains('/') ? 1 : int.parse(x); // ½ tablet still means "take one then"
    final half = [m.group(1), m.group(2), m.group(3)].any((x) => x!.contains('/'));
    return DraftField(Dose(morning: n(m.group(1)!), afternoon: n(m.group(2)!), night: n(m.group(3)!)), confidence: half ? 0.5 : min(conf, 0.9), seen: m.group(0));
  }
  final w = m.group(4)!.toLowerCase().replaceAll(RegExp(r'[.\s]+'), ' ').trim();
  final (Dose? d, double c) = switch (w) {
    'bd' || 'b d' || 'bid' || 'twice a day' || 'twice daily' => (Dose(morning: 1, afternoon: 0, night: 1), 0.75),
    'tds' || 't d s' || 'tid' || 'thrice a day' => (Dose(morning: 1, afternoon: 1, night: 1), 0.8),
    'hs' || 'h s' || 'at bed time' || 'at bedtime' || 'at night' => (Dose(morning: 0, afternoon: 0, night: 1), 0.8),
    'morning' => (Dose(morning: 1, afternoon: 0, night: 0), 0.7),
    // Once a day does not say when: the patient picks.
    'od' || 'o d' || 'once a day' || 'once daily' => (Dose(morning: 1, afternoon: 0, night: 0), 0.5),
    _ => (null, 0.0), // QID, SOS: no fixed morning/afternoon/night
  };
  return d == null ? const DraftField.none() : DraftField(d, confidence: min(conf, c), seen: m.group(0));
}

String? _timing(String s) {
  final t = s.toLowerCase();
  if (RegExp(r'after\s+(food|meals?|breakfast|lunch|dinner)|\ba/f\b|\bp\.?c\.?\b').hasMatch(t)) return 'after_food';
  if (RegExp(r'before\s+(food|meals?|breakfast|lunch|dinner)|empty\s+stomach|\bb/f\b|\ba\.?c\.?\b').hasMatch(t)) return 'before_food';
  if (RegExp(r'with\s+(food|meals?)').hasMatch(t)) return 'with_food';
  return null;
}

int? _days(String s) {
  final m = RegExp(r'(?:x|for|×)?\s*(\d{1,3})\s*(days?|d\b|weeks?|wks?|months?|mths?)', caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  final u = m.group(2)!.toLowerCase();
  final days = u.startsWith('w') ? n * 7 : u.startsWith('m') ? n * 30 : n;
  return days > 0 && days <= 365 ? days : null;
}

String _titleCase(String s) => s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty || RegExp(r'\d').hasMatch(w) || w.length <= 2 && w.toUpperCase() == w) return w;
      return w == w.toUpperCase() ? w[0] + w.substring(1).toLowerCase() : w;
    }).join(' ');

// ---- dates -------------------------------------------------------------------

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// Every date written on [text], day first as in India.
List<DateTime> datesIn(String text, DateTime today) {
  final out = <DateTime>[];
  int year(String y) {
    final n = int.parse(y);
    if (y.length == 4) return n;
    return n <= today.year % 100 ? 2000 + n : 1900 + n;
  }

  void add(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return; // 31 Feb
    if (dt.isAfter(DateTime(today.year, today.month, today.day)) || dt.year < 1990) return;
    out.add(dt);
  }

  for (final m in RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b').allMatches(text)) {
    add(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  for (final m in RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b').allMatches(text)) {
    add(year(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  for (final m in RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-/.,]*([A-Za-z]{3,9})[\s\-/.,]*(\d{4}|\d{2})\b').allMatches(text)) {
    final mon = _months[m.group(2)!.toLowerCase().substring(0, min(4, m.group(2)!.length))] ?? _months[m.group(2)!.toLowerCase().substring(0, 3)];
    if (mon != null) add(year(m.group(3)!), mon, int.parse(m.group(1)!));
  }
  for (final m in RegExp(r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b').allMatches(text)) {
    final mon = _months[m.group(1)!.toLowerCase().substring(0, 3)];
    if (mon != null) add(int.parse(m.group(3)!), mon, int.parse(m.group(2)!));
  }
  return out;
}

DraftField<DateTime> _date(List<OcrLine> lines, RecordKind kind, DateTime today) {
  DraftField<DateTime>? best;
  for (final l in lines) {
    final ds = datesIn(l.text, today);
    if (ds.isEmpty) continue;
    final n = l.norm;
    // Birth dates are not the document date.
    if (RegExp(r'\b(dob|d o b|date of birth|born)\b').hasMatch(n)) continue;
    final label = switch (kind) {
      RecordKind.report when RegExp(r'collect|sample|drawn|specimen').hasMatch(n) => 0.95,
      RecordKind.report when RegExp(r'regist|received|booking').hasMatch(n) => 0.8,
      RecordKind.report when RegExp(r'report|print|released|authori').hasMatch(n) => 0.75,
      _ when RegExp(r'\bdate\b|\bdt\b|dated').hasMatch(n) => 0.9,
      _ => 0.6,
    };
    final c = min(label, l.confidence + 0.05);
    if (best == null || c > best.confidence) best = DraftField(ds.first, confidence: c, seen: l.text);
  }
  return best ?? const DraftField.none();
}

// ---- title, place, doctor ------------------------------------------------------

const _panels = <String, List<String>>{
  'Complete blood count': ['complete blood count', 'complete haemogram', 'complete hemogram', 'haemogram', 'hemogram', 'cbc'],
  'Lipid panel': ['lipid profile', 'lipid panel'],
  'HbA1c': ['hba1c', 'glycosylated haemoglobin', 'glycosylated hemoglobin', 'glycated haemoglobin'],
  'Fasting glucose': ['fasting blood sugar', 'blood sugar fasting', 'glucose fasting', 'fasting plasma glucose'],
  'Thyroid profile': ['thyroid profile', 'thyroid function test', 'thyroid function', 'tft'],
  'Liver function': ['liver function test', 'liver function', 'lft'],
  'Kidney function': ['kidney function test', 'kidney function', 'renal function test', 'renal function', 'kft', 'rft'],
  'Urine routine': ['urine routine', 'urine examination', 'urine analysis', 'urinalysis', 'urine r m'],
  'Vitamin D': ['vitamin d', '25 oh vitamin d'],
  'Vitamin B12': ['vitamin b12'],
  'Iron studies': ['iron studies', 'iron profile'],
  'Electrolytes': ['serum electrolytes', 'electrolytes'],
};

DraftField<String> _title(List<OcrLine> lines, RecordKind kind, List<DraftField<LabResult>> results) {
  if (kind == RecordKind.prescription) return const DraftField.none();
  if (kind == RecordKind.scan) {
    for (final l in lines) {
      final m = RegExp(r'\b(x ray|xray|mri|hrct|ct scan|ct|ultrasound|usg|sonography|mammography|echocardiography|doppler)\b').firstMatch(l.norm);
      if (m != null && l.text.length <= 70) return DraftField(l.text.trim(), confidence: min(0.7, l.confidence), seen: l.text);
    }
    return const DraftField.none();
  }
  final hits = <String>[];
  String? seen;
  for (final l in lines) {
    // A panel name is a heading, not a row with a number after it.
    if (RegExp(r'(^| )\d+( |$)').hasMatch(l.norm)) continue;
    for (final e in _panels.entries) {
      if (!hits.contains(e.key) && e.value.any((a) => RegExp('(^| )${RegExp.escape(a)}( |\$)').hasMatch(l.norm))) {
        hits.add(e.key);
        seen ??= l.text;
      }
    }
  }
  if (hits.length == 1) return DraftField(hits.single, confidence: 0.9, seen: seen);
  if (hits.length == 2) return DraftField('${hits[0]} + ${hits[1]}', confidence: 0.75, seen: seen);
  if (hits.length > 2) return DraftField('Health check-up', confidence: 0.7, seen: seen);
  if (results.length == 1) return DraftField(_panelName(results.single.value!.analyte), confidence: 0.7);
  return results.isEmpty ? const DraftField.none() : DraftField('Blood test', confidence: 0.5);
}

String _panelName(String analyte) => switch (analyte) {
      'glucose_fasting' => 'Fasting glucose',
      'hba1c' => 'HbA1c',
      'tsh' => 'Thyroid profile',
      'vitamin_d' => 'Vitamin D',
      'vitamin_b12' => 'Vitamin B12',
      'ferritin' => 'Ferritin',
      'creatinine' => 'Kidney function',
      _ => 'Blood test',
    };

/// Labs and hospital chains, normalised → as they write their own name.
const knownPlaces = <String, String>{
  'dr lal pathlabs': 'Dr Lal PathLabs', 'lal pathlabs': 'Dr Lal PathLabs', 'lal path labs': 'Dr Lal PathLabs',
  'thyrocare': 'Thyrocare', 'metropolis': 'Metropolis Healthcare', 'srl diagnostics': 'SRL Diagnostics', 'agilus': 'Agilus Diagnostics',
  'redcliffe': 'Redcliffe Labs', 'healthians': 'Healthians', 'max lab': 'Max Lab', 'neuberg': 'Neuberg Diagnostics',
  'vijaya diagnostic': 'Vijaya Diagnostic Centre', 'pathkind': 'Pathkind Labs', 'tata 1mg': 'Tata 1mg Labs', '1mg labs': 'Tata 1mg Labs',
  'orange health': 'Orange Health Labs', 'suburban diagnostics': 'Suburban Diagnostics', 'medall': 'Medall', 'apollo diagnostics': 'Apollo Diagnostics',
  'apollo hospital': 'Apollo Hospitals', 'apollo clinic': 'Apollo Clinic', 'fortis': 'Fortis', 'manipal hospital': 'Manipal Hospitals',
  'narayana health': 'Narayana Health', 'medanta': 'Medanta', 'aiims': 'AIIMS', 'max super speciality': 'Max Healthcare', 'max healthcare': 'Max Healthcare',
};

DraftField<String> _place(List<OcrLine> lines, RecordKind kind) {
  for (final l in lines) {
    for (final e in knownPlaces.entries) {
      if (RegExp('(^| )${RegExp.escape(e.key)}( |\$)').hasMatch(l.norm)) return DraftField(e.value, confidence: 0.9, seen: l.text);
    }
  }
  // Otherwise the letterhead: an early line that names a lab or a clinic.
  for (final l in lines.take(12)) {
    if (RegExp(r'^dr\b').hasMatch(l.norm)) continue;
    if (RegExp(r'laborator|diagnostic|patholog|path lab|hospital|clinic|medical cent|health ?care|nursing home|imaging|polyclinic').hasMatch(l.norm)) {
      final name = l.text.split(RegExp(r'[,|]')).first.trim();
      if (name.length >= 4 && name.length <= 60) return DraftField(name, confidence: min(0.6, l.confidence), seen: l.text);
    }
  }
  return const DraftField.none();
}

final _drName = RegExp(r'\b(?:Dr|DR)(?:\.\s*|\s+)([A-Z][A-Za-z.]*(?:\s+[A-Z][A-Za-z.]*){0,3})');
const _degrees = {'mbbs', 'md', 'ms', 'dnb', 'mrcp', 'frcs', 'dm', 'mch', 'bams', 'bhms', 'reg', 'consultant', 'physician', 'mobile', 'ph', 'phone'};

DraftField<String> _doctor(List<OcrLine> lines, RecordKind kind) {
  DraftField<String>? best;
  for (final l in lines) {
    // Only the words in the doctor's own column: "Ref. By: Dr X | Collected".
    final k = l.words.indexWhere((w) => RegExp(r'^(Dr|DR)\.?').hasMatch(w.text));
    if (k < 0) continue;
    final own = l.words.where((w) => w.line == l.words[k].line && w.left >= l.words[k].left).map((w) => w.text).join(' ');
    final m = _drName.firstMatch(own);
    if (m == null) continue;
    final parts = <String>[];
    for (final w in m.group(1)!.trim().split(RegExp(r'\s+'))) {
      if (_degrees.contains(normalize(w))) break;
      parts.add(w.replaceAll(RegExp(r'[.,]+$'), ''));
    }
    final name = parts.join(' ').trim();
    if (name.length < 3 || RegExp(r'^lal\b', caseSensitive: false).hasMatch(name)) continue;
    // On a lab report the doctor is the one who referred, not the pathologist.
    final referred = RegExp(r'\bref|referred|consultant\b').hasMatch(l.norm);
    final c = kind == RecordKind.report ? (referred ? 0.85 : 0.5) : 0.8;
    if (best == null || c > best.confidence) best = DraftField('Dr ${_titleCase(name)}', confidence: min(c, l.confidence + 0.05), seen: l.text);
    if (kind == RecordKind.prescription) break; // the letterhead comes first
  }
  return best ?? const DraftField.none();
}
