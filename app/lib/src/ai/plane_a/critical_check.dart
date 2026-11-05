import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../insight.dart';
import 'banned_phrases.dart';
import 'critical_values.dart';
import 'reference_ranges.dart';

/// One value held against the danger limits.
class CriticalVerdict {
  const CriticalVerdict({this.severity, this.finding, this.unchecked});
  static const clear = CriticalVerdict();

  /// Null when no limit was crossed, or none could be applied.
  final Severity? severity;

  /// States the value and the limit it crossed, then stops.
  final String? finding;

  /// Why the value could not be held against a limit. Never treated as fine.
  final NotCheckedReason? unchecked;
}

/// The always-on danger-level check: deterministic, on the phone, and run on
/// every lab value as it is saved, whether or not Insights is on.
///
/// **How it reads the value.** It does not. This code is pure: the patient's
/// own save path hands it the value in hand, the one the patient just typed
/// or ticked, and it reads no store. Because no record is read, there is no
/// `RecordAccess` read to audit, no grant to hold, and no agent actor: nothing
/// here touches `ConsentStore` (#5, #11), and the Insights grant still governs
/// everything that looks through the history. The save it runs inside is
/// already audited, and that entry names any test that raised a prompt (#13).
///
/// A range and a danger limit answer different questions, so this runs
/// without any range: a printed range that passes, an adult range that must
/// not be used for a child, and a missing range all leave it unaffected.
///
/// It says what it found or that it could not tell. It never says a value is
/// fine: a value with no limit crossed produces nothing at all, and a covered
/// value it cannot judge comes back in [InsightRun.unresolved].
abstract final class CriticalCheck {
  /// An older result is not a live emergency: a bulk scan of old reports must
  /// not send anyone to casualty. It still reaches a person today.
  /// VERIFY WITH CLINICIAN.
  static const staleAfter = Duration(days: 7);

  static CriticalLimit? limitFor(String analyte) => criticalLimits.where((l) => l.analytes.contains(analyte)).firstOrNull;

  /// [patient] is null only where no person is known yet; the age rule then
  /// does not apply.
  static CriticalVerdict result({required Patient? patient, required LabResult result, required DateTime resultDate, required DateTime at}) {
    final limit = limitFor(result.analyte);
    if (limit == null) return CriticalVerdict.clear;
    final highSide = patient == null || patient.ageAt(at) >= limit.highSideFromAge;
    final raw = result.unit.trim();
    final spelled = normaliseUnit(raw);
    final known = limit.forms.where((f) => f.spellings.contains(spelled)).firstOrNull;
    final name = analyteName(result.analyte);
    final when = dateLabel(resultDate);

    if (known != null) {
      final v = known.toCanonical(result.value);
      final s = limit.classify(v, highSide: highSide);
      if (s == null) {
        // Above a limit that is not applied at this age: unjudged, not fine.
        return limit.classify(v) != null ? const CriticalVerdict(unchecked: NotCheckedReason.dangerLimitNotChecked) : CriticalVerdict.clear;
      }
      final about = known.isCanonical ? '' : ' (about ${_fmt(v)} ${limit.unit})';
      return CriticalVerdict(severity: s, finding: '$name was ${_fmt(result.value)} $raw$about on $when. ${_limitSentence(limit, v, s)}');
    }

    // No unit, or one that does not fit this test. Try every reading of the
    // number that could be real, and answer for the worst of them.
    Severity? worst;
    double? worstV;
    for (final f in limit.forms) {
      final v = f.toCanonical(result.value);
      if (v < limit.plausible.$1 || v > limit.plausible.$2) continue;
      final s = limit.classify(v, highSide: highSide);
      if (s != null && (worst == null || s.index > worst.index)) {
        worst = s;
        worstV = v;
      }
    }
    if (worst == null) return const CriticalVerdict(unchecked: NotCheckedReason.dangerLimitNotChecked);
    final stated = raw.isEmpty ? 'no unit on the report' : 'unit "$raw" not recognised';
    return CriticalVerdict(
      severity: worst,
      finding: '$name was ${_fmt(result.value)} ($stated) on $when. Read as ${_fmt(worstV!)} ${limit.unit}: ${_limitSentence(limit, worstV, worst)}',
    );
  }

  /// Every lab value on [record], as it is saved.
  static InsightRun record({required Patient? patient, required HealthRecord record, required DateTime at}) {
    final out = <Insight>[];
    final unresolved = <NotChecked>[];
    final stale = at.difference(record.effectiveDate) > staleAfter;
    for (final res in record.results) {
      final v = result(patient: patient, result: res, resultDate: record.effectiveDate, at: at);
      if (v.unchecked != null) {
        unresolved.add(NotChecked(recordId: record.id, analyte: res.analyte, value: res.value, unit: res.unit, reason: v.unchecked!));
      }
      if (v.severity == null) continue;
      final severity = stale ? Severity.contactDoctorToday : v.severity!;
      out.add(Insight(
        kind: InsightKind.critical,
        severity: severity,
        analyte: res.analyte,
        finding: stale ? '${v.finding} This result is more than a week old.' : v.finding!,
        action: actionFor(severity),
        evidence: [record.id],
      ));
    }
    return finish(out, unresolved);
  }

  /// Applies the banned-phrase rule (#9) and puts the worst first.
  static InsightRun finish(List<Insight> out, List<NotChecked> unresolved) {
    final kept = [for (final i in out) if (firstBannedPhrase('${i.finding} ${i.action}') == null) i];
    kept.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return InsightRun(insights: kept, unresolved: unresolved, dropped: out.length - kept.length);
  }

  static String _limitSentence(CriticalLimit limit, double v, Severity s) {
    final (side, bound) = limit.crossed(v, s);
    final need = s == Severity.urgentCare ? 'urgent attention' : 'attention today';
    return 'LifeTrack treats anything $side ${_fmt(bound)} ${limit.unit} as needing $need.';
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    final short = double.parse(v.toStringAsFixed(2));
    return short == short.roundToDouble() ? short.toStringAsFixed(0) : '$short';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}
