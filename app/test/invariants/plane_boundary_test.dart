import 'package:flutter_test/flutter_test.dart';

import 'source.dart';

void main() {
  final lib = dartFiles('lib');
  String rel(f) => f.path.replaceAll(r'\', '/');

  test('exactly one file outside plane_c imports plane_c: the cloud adapter', () {
    final importers = [
      for (final f in lib)
        if (!rel(f).contains('/ai/plane_c/') && RegExp(r"import '[^']*plane_c/").hasMatch(codeOf(f))) rel(f),
    ];
    expect(importers, ['lib/src/app/cloud_escalation_adapter.dart']);
  });

  group('agents (lib/src/ai) never', () {
    final ai = [for (final f in lib) if (rel(f).startsWith('lib/src/ai/')) f];

    test('issue a grant (CLAUDE.md #5)', () {
      for (final f in ai) {
        final code = codeOf(f);
        expect(code.contains('.issue('), isFalse, reason: rel(f));
        expect(code.contains('grants.dart'), isFalse, reason: rel(f));
      }
    });

    test('read the repository directly — only through RecordAccess', () {
      for (final f in ai) {
        final code = codeOf(f);
        expect(code.contains('record_repository.dart'), isFalse, reason: rel(f));
        expect(code.contains('recordsOf('), isFalse, reason: rel(f));
      }
    });

    test('reach the clinical share (CLAUDE.md #1a: only a patient approval shares)', () {
      for (final f in ai) {
        expect(RegExp(r"import '[^']*share/").hasMatch(codeOf(f)), isFalse, reason: rel(f));
      }
    });

    test('touch the Emergency ID', () {
      for (final f in ai) {
        expect(RegExp(r"import '[^']*emergency/").hasMatch(codeOf(f)), isFalse, reason: rel(f));
      }
    });

    test('read wall-clock time — the clock is always a parameter', () {
      for (final f in ai) {
        expect(codeOf(f).contains('DateTime.now()'), isFalse, reason: rel(f));
      }
    });
  });

  test('the view layer never computes abnormality (CLAUDE.md #8, ruling A)', () {
    final ui = [for (final f in lib) if (rel(f).startsWith('lib/src/ui/')) f];
    const engineSymbols = ['referenceRangeFor', 'matchesUnit', 'criticalLimits', 'DeterministicInsights', '.contains(res.value', 'isAbove('];
    for (final f in ui) {
      final code = codeOf(f);
      for (final s in engineSymbols) {
        expect(code.contains(s), isFalse, reason: '${rel(f)} uses $s');
      }
    }
  });

  test('main.dart is wiring only', () {
    final code = codeOf(lib.firstWhere((f) => rel(f) == 'lib/main.dart'));
    expect(RegExp(r'\bclass\s').hasMatch(code), isFalse);
    expect(code.contains('plane_'), isFalse);
  });

  test('nothing in lib/ can open a socket', () {
    final banned = RegExp(r'\b(HttpClient|Socket|RawSocket|WebSocket|SecureSocket|HttpServer|NetworkInterface|InternetAddress)\b');
    for (final f in lib) {
      expect(banned.hasMatch(codeOf(f)), isFalse, reason: rel(f));
    }
  });
}
