import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source.dart';

/// Platform properties the security story depends on. Each is a test so that
/// changing it is a visible custody event, not a silent diff.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('the release manifest requests no INTERNET permission', () {
    // Debug and profile manifests add it for the Flutter tool; release must not.
    expect(manifest.contains('android.permission.INTERNET'), isFalse);
  });

  test('Android backup and device transfer are refused', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
  });

  test('release is never signed with the debug key, and is shrunk by R8', () {
    expect(gradle.contains('getByName("debug")'), isFalse);
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(File('android/app/proguard-rules.pro').existsSync(), isTrue);
  });

  test('iOS files are protected until first unlock, in every Runner configuration', () {
    final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(ent, contains('NSFileProtectionComplete'));
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(RegExp('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;').allMatches(pbx), hasLength(3));
  });

  test('dependencies are the allowlist — none can reach the network', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final deps = RegExp(r'^dependencies:\n((?:  .*\n|\s*\n|  #.*\n)*)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    final names = RegExp(r'^  ([a-z_]+):', multiLine: true).allMatches(deps).map((m) => m.group(1)).toSet();
    expect(names, {'flutter', 'cupertino_icons', 'cryptography', 'path_provider', 'flutter_secure_storage'});
    expect(pubspec.contains('google_fonts'), isFalse, reason: 'runtime font download is network egress');
  });

  test('fonts are bundled', () {
    for (final f in ['BricolageGrotesque', 'PublicSans', 'SplineSansMono']) {
      expect(File('fonts/$f.ttf').existsSync(), isTrue, reason: f);
    }
  });

  test('every release-mode guard throws; none asserts (CLAUDE.md #2a)', () {
    // Derived, not listed: covers the next stand-in the day it is written.
    final guarded = [for (final f in dartFiles('lib')) if (codeOf(f).contains('kReleaseMode')) f];
    expect(guarded, isNotEmpty);
    for (final f in guarded) {
      final code = codeOf(f);
      expect(RegExp(r'assert\s*\(\s*!?\s*kReleaseMode').hasMatch(code), isFalse, reason: f.path);
      expect(RegExp(r'if\s*\(\s*kReleaseMode\s*\)\s*\{\s*throw').hasMatch(code), isTrue, reason: f.path);
    }
  });
}
