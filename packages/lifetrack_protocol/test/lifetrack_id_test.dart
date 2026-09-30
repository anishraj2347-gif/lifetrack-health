import 'dart:math';

import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('12 digits, starts with 1, and validates', () {
    final r = Random(7);
    for (var i = 0; i < 2000; i++) {
      final id = LifeTrackId.generate(r);
      expect(id, matches(RegExp(r'^1\d{11}$')));
      expect(LifeTrackId.parse(id), id);
      expect(LifeTrackId.parse(LifeTrackId.display(id)), id);
    }
  });

  test('every single wrong digit and every neighbour swap is caught', () {
    final r = Random(11);
    for (var n = 0; n < 300; n++) {
      final id = LifeTrackId.generate(r);
      for (var i = 1; i < 12; i++) {
        for (var d = 0; d < 10; d++) {
          if ('$d' == id[i]) continue;
          expect(LifeTrackId.parse(id.replaceRange(i, i + 1, '$d')), isNull);
        }
        if (i < 11 && id[i] != id[i + 1]) {
          expect(LifeTrackId.parse(id.substring(0, i) + id[i + 1] + id[i] + id.substring(i + 2)), isNull);
        }
      }
    }
  });

  test('can never be an Aadhaar number (those never start with 0 or 1)', () {
    expect(LifeTrackId.parse('234567890123'), isNull);
    expect(LifeTrackId.parse('012345678901'), isNull);
  });
}
