import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack_doctor/app_version.dart';

void main() {
  test('the version shown on Profile is the one in pubspec.yaml', () {
    final v = RegExp(r'^version: (\S+?)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(doctorAppVersion, v);
  });
}
