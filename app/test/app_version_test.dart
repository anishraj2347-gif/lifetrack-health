import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_version.dart';

void main() {
  test('the version on Me matches pubspec.yaml', () {
    final m = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m?.group(1), appVersion);
  });
}
