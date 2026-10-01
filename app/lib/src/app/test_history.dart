import '../model/health_record.dart';

/// One measured test across all reports, newest first.
class TestSeries {
  const TestSeries(this.analyte, this.points);
  final String analyte;

  /// (record, result), newest first.
  final List<(HealthRecord, LabResult)> points;
  (HealthRecord, LabResult) get latest => points.first;
}

/// "Tests you already have": every measured test with its history, and the
/// reports and scans that carry no typed values (the original is the
/// result). Ordered so the most recent appear first. Nothing here judges a
/// value or calls a result current or out of date — it states age and source.
class TestHistory {
  TestHistory(Iterable<HealthRecord> records) {
    final byAnalyte = <String, List<(HealthRecord, LabResult)>>{};
    for (final r in records) {
      if (r.kind == RecordKind.report && r.results.isNotEmpty) {
        for (final x in r.results) {
          byAnalyte.putIfAbsent(x.analyte, () => []).add((r, x));
        }
      } else if (r.kind == RecordKind.scan || r.kind == RecordKind.report) {
        documents.add(r);
      }
    }
    for (final e in byAnalyte.entries) {
      e.value.sort((a, b) => b.$1.effectiveDate.compareTo(a.$1.effectiveDate));
      series.add(TestSeries(e.key, e.value));
    }
    series.sort((a, b) => b.latest.$1.effectiveDate.compareTo(a.latest.$1.effectiveDate));
    documents.sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
  }

  final List<TestSeries> series = [];
  final List<HealthRecord> documents = [];

  bool get isEmpty => series.isEmpty && documents.isEmpty;
  int get count => series.length + documents.length;
}

/// "today", "3 days ago", "5 weeks ago", "4 months ago", "2 years ago".
String ageOf(int days) => days <= 0
    ? 'today'
    : days == 1
        ? 'yesterday'
        : days < 14
            ? '$days days ago'
            : days < 60
                ? '${(days / 7).round()} weeks ago'
                : days < 730
                    ? '${(days / 30.4).round()} months ago'
                    : '${(days / 365).round()} years ago';
