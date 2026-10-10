import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/widgets/parts.dart';

/// Every photo the screens name is bundled, and small enough to keep the
/// APK lean.
void main() {
  test('every bundled photo exists and is under 250 KB', () {
    for (final p in [Photos.family, Photos.report, Photos.doctor, Photos.pills, Photos.reading, Photos.parent]) {
      final f = File(p);
      expect(f.existsSync(), isTrue, reason: p);
      expect(f.lengthSync(), lessThan(250 * 1024), reason: p);
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/photos/'));
  });
}
