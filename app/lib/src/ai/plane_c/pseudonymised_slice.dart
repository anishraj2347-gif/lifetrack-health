import 'dart:convert';

import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../plane_a/reference_ranges.dart';

/// What Plane C may send. A type, not an adjective on a parameter: the only
/// way to build one is [fromRecords], which keeps analyte, value, unit and a
/// coarse relative month — no name, no date of birth, no record id, no doctor,
/// no facility, no free text.
class PseudonymisedSlice {
  PseudonymisedSlice._(this.ageBand, this.sex, this.entries);

  static const maxEntries = 40;

  final String ageBand;
  final String sex;
  final List<SliceEntry> entries;

  static PseudonymisedSlice fromRecords({required Patient patient, required List<HealthRecord> records, required DateTime at}) {
    final age = patient.ageAt(at);
    final band = '${(age ~/ 10) * 10}–${(age ~/ 10) * 10 + 9}';
    final entries = <SliceEntry>[
      for (final r in records)
        for (final res in r.results)
          // Only analytes on the known table: a free-text analyte name is a
          // channel for identifying text.
          if (analyteNames.containsKey(res.analyte))
            SliceEntry(
              analyte: res.analyte,
              value: res.value,
              unit: res.unit,
              monthsAgo: ((at.year - r.date.year) * 12 + at.month - r.date.month).clamp(0, 600),
            ),
    ]..sort((a, b) => a.monthsAgo.compareTo(b.monthsAgo));
    final bounded = entries.take(maxEntries).toList(growable: false);
    final slice = PseudonymisedSlice._(band, patient.sex.name, bounded);
    slice._assertNoIdentifiers(patient);
    return slice;
  }

  /// Checked after assembly, against the assembled bytes.
  void _assertNoIdentifiers(Patient patient) {
    final text = canonical.toLowerCase();
    final nameParts = patient.name.toLowerCase().split(RegExp(r'\s+')).where((p) => p.length > 2);
    if (nameParts.any(text.contains) ||
        text.contains(patient.id.toLowerCase()) ||
        RegExp(r'\d{10}').hasMatch(text) ||
        text.contains(patient.dateOfBirth.year.toString())) {
      throw StateError('Pseudonymised slice contains an identifier.');
    }
  }

  /// The exact bytes that would leave. Shown to the patient before the tap
  /// and compared against the payload at send time.
  String get canonical => jsonEncode({
        'ageBand': ageBand,
        'sex': sex,
        'entries': [for (final e in entries) e.toJson()],
      });
}

class SliceEntry {
  const SliceEntry({required this.analyte, required this.value, required this.unit, required this.monthsAgo});
  final String analyte;
  final double value;
  final String unit;
  final int monthsAgo;

  Map<String, Object?> toJson() => {'a': analyte, 'v': value, 'u': unit, 'm': monthsAgo};
}
