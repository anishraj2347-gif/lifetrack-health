/// What the UI sees of Plane C. The UI can neither mint a `HumanAction` nor
/// assemble a payload — it can only show a disclosure and report a tap.
abstract interface class CloudEscalation {
  /// Whether Tier 2 is switched on for this region right now.
  bool isAvailable(DateTime at);

  /// The exact payload that would leave, for the patient to read first.
  Disclosure prepare(String patientId, DateTime at);

  /// Called from the confirm button's handler, with the time of the tap.
  Future<CloudOutcome> confirm(Disclosure disclosure, DateTime tappedAt);
}

class Disclosure {
  const Disclosure({required this.patientId, required this.lines, required this.payload});
  final String patientId;

  /// Human-readable rendering of [payload], one line per value.
  final List<String> lines;
  final String payload;
}

class CloudOutcome {
  const CloudOutcome({required this.statements, this.refusal});
  final List<String> statements;
  final String? refusal;
}
