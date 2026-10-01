import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../audit/audit_log.dart';
import '../emergency/emergency_card.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';
import '../model/vital_reading.dart';

/// Everything held about one person, as one zip they can keep or send on:
/// `summary.html` to read or print, `records.json` for another app, and the
/// original pages. Values are copied as recorded — nothing is judged.
class RecordExport {
  RecordExport({
    required this.patient,
    required this.records,
    required this.profile,
    required this.emergency,
    required this.audit,
    this.vitals = const [],
    required this.originals,
    required this.at,
  });

  final Patient patient;
  final List<HealthRecord> records;
  final ClinicalProfile profile;
  final EmergencyCard emergency;
  final List<AuditEntry> audit;

  /// Home BP and sugar readings, newest first.
  final List<VitalReading> vitals;

  /// Original pages by record id.
  final Map<String, List<Uint8List>> originals;
  final DateTime at;

  static const formatVersion = 1;

  String get fileName {
    final slug = patient.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return 'lifetrack-$slug-${at.toIso8601String().substring(0, 10)}.zip';
  }

  Uint8List zip() {
    final a = Archive();
    void add(String name, List<int> bytes) => a.addFile(ArchiveFile(name, bytes.length, bytes));
    add('records.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(json())));
    add('summary.html', utf8.encode(html()));
    for (final e in originals.entries) {
      for (var i = 0; i < e.value.length; i++) {
        add('originals/${e.key}-page${i + 1}.jpg', e.value[i]);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  Map<String, Object?> json() => {
        'format': 'lifetrack-export',
        'formatVersion': formatVersion,
        'exportedAt': at.toIso8601String(),
        'patient': patient.toJson(),
        'emergencyId': emergency.toJson(),
        'profile': profile.toJson(),
        'records': [
          for (final r in records)
            {
              ...r.toJson(),
              'provenance': r.provenance.name,
              if (originals[r.id] != null) 'originals': [for (var i = 0; i < originals[r.id]!.length; i++) 'originals/${r.id}-page${i + 1}.jpg'],
            },
        ],
        'homeReadings': [for (final v in vitals) v.toJson()],
        'accessLog': [for (final e in audit) e.toJson()],
      };

  static String _source(Provenance p) => switch (p) {
        Provenance.signed => 'signed by the lab or doctor',
        Provenance.photoOfReport => 'from a photo of the report',
        Provenance.patientTyped => 'typed in by the patient',
      };

  String html() {
    String h(Object? s) => const HtmlEscape(HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true)).convert('${s ?? ''}');
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    final byDate = [...records]..sort((x, y) => y.date.compareTo(x.date));
    final b = StringBuffer()
      ..write('<!doctype html><html lang="en"><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width,initial-scale=1">'
          '<title>${h(patient.name)} — LifeTrack records</title><style>'
          'body{font:15px/1.5 system-ui,sans-serif;max-width:760px;margin:24px auto;padding:0 16px;color:#111}'
          'h1{margin:0}h2{margin-top:28px;border-bottom:1px solid #ccc;padding-bottom:4px}'
          '.m{color:#555;font-size:13px}.r{padding:10px 0;border-bottom:1px solid #eee}'
          'table{border-collapse:collapse;margin-top:6px}td{padding:2px 12px 2px 0}'
          '.w{background:#FEF3C7;color:#78350F;padding:10px 12px;border-radius:8px}'
          '</style></head><body>')
      ..write('<h1>${h(patient.name)}</h1><p class="m">Exported from LifeTrack on ${d(at)}. '
          'Values are copied as recorded; this file does not interpret them.</p>')
      ..write('<p class="w">This file is not encrypted. Anyone who has it can read it.</p>')
      ..write('<h2>Emergency ID</h2>');
    for (final (label, v) in [
      ('Blood type', emergency.bloodType),
      ('Allergies', emergency.allergies),
      ('Ongoing conditions', emergency.conditions),
      ('Current medicines', emergency.medications),
      ('Emergency contact', [emergency.contactName, emergency.contactRelation, emergency.contactPhone].where((x) => x.isNotEmpty).join(' · ')),
    ]) {
      b.write('<div>${h(label)}: <b>${h(v.isEmpty ? '—' : v)}</b></div>');
    }
    if (profile.allergies.isNotEmpty || profile.conditions.isNotEmpty) {
      b.write('<h2>Allergies and conditions</h2>');
      for (final a in profile.allergies) {
        b.write('<div>Allergy: ${h(a.substance)}${a.reaction == null ? '' : ' — ${h(a.reaction)}'}</div>');
      }
      for (final c in profile.conditions) {
        b.write('<div>Condition: ${h(c.name)}${c.sinceYear == null ? '' : ' (since ${c.sinceYear})'}</div>');
      }
    }
    if (profile.familyIllnesses.isNotEmpty) {
      b.write('<h2>Family illnesses (as you reported them)</h2>');
      for (final f in profile.familyIllnesses) {
        b.write('<div>${h(f.relation.name)}: ${h(f.condition)}</div>');
      }
    }
    b.write('<h2>Records</h2>');
    for (final r in byDate) {
      b.write('<div class="r"><b>${h(r.title)}</b> <span class="m">${h(r.kind.name)} · ${d(r.date)}');
      for (final x in [r.doctor, r.facility, r.labName]) {
        if (x != null) b.write(' · ${h(x)}');
      }
      b.write(' · ${h(_source(r.provenance))}</span>');
      if (r.dose != null) b.write('<div>Dose ${h(r.dose!.display)} (morning-afternoon-night)</div>');
      if (r.instructions != null) b.write('<div>${h(r.instructions)}</div>');
      if (r.endDate != null) b.write('<div class="m">Course ends ${d(r.endDate!)}</div>');
      if (r.results.isNotEmpty) {
        b.write('<table>');
        for (final x in r.results) {
          final lo = x.printedLow, hi = x.printedHigh;
          final range = switch ((lo, hi)) {
            (final double l, final double u) => 'lab range ${n(l)}–${n(u)}',
            (null, final double u) => 'lab range ${n(u)} or below',
            (final double l, null) => 'lab range ${n(l)} or above',
            _ => '',
          };
          b.write('<tr><td>${h(x.analyte)}</td><td><b>${n(x.value)} ${h(x.unit)}</b></td><td class="m">${h(range)}</td></tr>');
        }
        b.write('</table>');
      }
      final pages = originals[r.id]?.length ?? 0;
      for (var i = 0; i < pages; i++) {
        b.write('<div><a href="originals/${h(r.id)}-page${i + 1}.jpg">Original, page ${i + 1}</a></div>');
      }
      b.write('</div>');
    }
    if (vitals.isNotEmpty) {
      b.write('<h2>Home readings</h2>');
      for (final v in vitals) {
        b.write('<div>${d(v.at)} ${v.at.toIso8601String().substring(11, 16)} · ${h(v.display)}</div>');
      }
    }
    b.write('<p class="m">The access log, and every field above in machine-readable form, is in records.json.</p></body></html>');
    return b.toString();
  }
}
