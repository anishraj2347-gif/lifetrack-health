/// Phrases no Tier 1 output may contain (CLAUDE.md #9).
///
/// Covers both halves: assertions ("you have", "diagnosis") and forecasts
/// ("risk of", "may indicate", "progression to"). A forecast is exactly what
/// Tier 2 certification gates, so missing the hedged forms would be missing
/// the half that matters.
const bannedPhrases = <String>[
  // assertions
  'diagnos', 'you have', 'you are', 'you suffer', 'disease', 'disorder',
  'prediabet', 'diabetic', 'anaemic', 'anemic', 'hypothyroid', 'hyperthyroid',
  'kidney failure', 'renal failure', 'is normal', 'are normal', 'healthy',
  'nothing to worry', 'no need to',
  // forecasts and hedges
  'risk of', 'at risk', 'risk score', 'likely', 'unlikely', 'probability', 'chance of',
  'may indicate', 'might indicate', 'could indicate', 'indicates', 'indicative',
  'suggests', 'suggestive', 'consistent with', 'sign of', 'signs of',
  'progression to', 'progressing', 'will develop', 'predict',
  // treatment advice
  'stop taking', 'increase your dose', 'reduce your dose', 'skip',
];

/// Case-insensitive; true when [text] contains a banned phrase.
String? firstBannedPhrase(String text) {
  final t = text.toLowerCase();
  for (final p in bannedPhrases) {
    if (t.contains(p)) return p;
  }
  return null;
}
