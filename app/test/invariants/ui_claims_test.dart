import 'package:flutter_test/flutter_test.dart';

import 'source.dart';

/// CLAUDE.md #2 and #9b: no patient-facing string may assert a security or
/// immutability property the code does not deliver.
///
/// Tested on the claim's *subject*, not on a list of literal phrases. The
/// literal blocklist was walked around four times by rewording ("cannot open
/// it" slipped past "cannot read it"). Here any sentence whose subject is
/// LifeTrack / the server / anyone else, with a negation and an access verb,
/// is a claim of unreconstructibility — however it is worded.
final _subject = RegExp(r"\b(lifetrack|we|us|our (server|servers|team|staff)|the server|nobody|no one|anyone|anybody|no-one)\b");
final _negation = RegExp(r"\b(cannot|can't|can not|never|unable|won't|not able|no way|impossible)\b");
final _access = RegExp(r"\b(read|reads|open|opens|access|see|sees|view|decrypt|decrypts|unlock|reconstruct|look at)\b");
final _absolutes = RegExp(
  r"unreconstructible|zero[- ]knowledge|end[- ]to[- ]end encrypted|military[- ]grade|unhackable|nothing else can|no one else can|only you can (read|open|see|access|view)",
);
final _negativeSubject = RegExp(r"\b(nobody|no one|no-one)\b.*\b(can|could|will|is able to)\b.*\b(access|read|see|open|view|decrypt)\b");
final _immutability = RegExp(r"(cannot|can't|can never|will never) be (edited|deleted|changed|altered|removed|erased)");

List<String> violations(String text) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'[.!?\n]|—| - '))) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) continue;
    // Whole sentence, not clause: "LifeTrack keeps a backup, and cannot open
    // it" puts the subject and the claim in different clauses.
    if (_subject.hasMatch(s) && _negation.hasMatch(s) && _access.hasMatch(s)) out.add(raw.trim());
    if (_absolutes.hasMatch(s) || _immutability.hasMatch(s) || _negativeSubject.hasMatch(s)) out.add(raw.trim());
  }
  return out;
}

void main() {
  group('the detector itself', () {
    test('catches every claim the audit found, in their original wording', () {
      for (final bad in [
        'LifeTrack keeps an encrypted backup of doctor-issued documents only, and cannot open it.',
        'This log cannot be edited or deleted — not by a doctor, not by LifeTrack, not by you.',
        'It opens your backup and nothing else can.',
        'We cannot read your records.',
        'Your vault is unreconstructible by anyone but you.',
        'Nobody at LifeTrack can ever see your data.',
      ]) {
        expect(violations(bad), isNotEmpty, reason: bad);
      }
    });

    test('lets true statements through', () {
      for (final ok in [
        'LifeTrack never receives this phrase and cannot reset it for you.',
        'LifeTrack has no way to edit or remove an entry.',
        'Nobody has access right now.',
        'A stranger can read this.',
      ]) {
        expect(violations(ok), isEmpty, reason: ok);
      }
    });
  });

  test('no string in the app makes an unreconstructibility or immutability claim', () {
    final found = <String>[];
    for (final f in dartFiles('lib')) {
      for (final v in violations(stringsOf(codeOf(f)))) {
        found.add('${f.path}: "$v"');
      }
    }
    expect(found, isEmpty);
  });
}
