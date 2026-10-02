import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'source.dart';

/// Platform properties the security story depends on. Each is a test so that
/// changing it is a visible custody event, not a silent diff.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('INTERNET is requested once, for the encrypted relay only (CLAUDE.md #3)', () {
    // Approved custody change, 30 Sep 2026. Any second network permission or
    // network-capable file is a new custody event and must fail here first.
    expect(RegExp('android.permission.INTERNET').allMatches(manifest), hasLength(1));
  });

  test('plain HTTP is allowed only to the loopback relay', () {
    expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
    final nsc = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    expect(nsc, contains('<base-config cleartextTrafficPermitted="false" />'));
    final domains = RegExp(r'<domain[^>]*>([^<]+)</domain>').allMatches(nsc).map((m) => m.group(1)).toSet();
    expect(domains, {'127.0.0.1', 'localhost'});
  });

  test('permissions plugins add but scanning does not need are stripped', () {
    for (final p in ['RECORD_AUDIO', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'ACCESS_NETWORK_STATE']) {
      expect(manifest, contains('android.permission.$p" tools:node="remove"'), reason: p);
    }
  });

  test('"Share to LifeTrack" takes photos and PDFs only, read in memory from other apps', () {
    final filters = RegExp(r'<intent-filter>(.*?)</intent-filter>', dotAll: true).allMatches(manifest).map((m) => m.group(1)!).where((f) => f.contains('.SEND')).toList();
    expect(filters, hasLength(2));
    for (final f in filters) {
      final types = RegExp(r'android:mimeType="([^"]+)"').allMatches(f).map((m) => m.group(1)).toSet();
      expect(types, {'image/*', 'application/pdf'});
    }
    final activity = File('android/app/src/main/kotlin/health/lifetrack/lifetrack/MainActivity.kt').readAsStringSync();
    expect(activity, contains('uri.scheme != "content" || uri.authority?.startsWith(packageName) == true'), reason: 'no file:// paths, none of our own files');
    expect(activity.contains('FileOutputStream') || activity.contains('cacheDir'), isFalse, reason: 'shared files stay in memory (#7c)');
  });

  test('scanned pages are read on the phone by the pinned Tesseract model (#1)', () async {
    final model = File('android/app/src/main/assets/tessdata/eng.traineddata');
    // tessdata_best eng, from github.com/tesseract-ocr/tessdata_best. A
    // different model is a visible change, not a silent one.
    final sha = await Sha256().hash(model.readAsBytesSync());
    expect(sha.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), '8280aed0782fe27257a68ea10fe7ef324ca0f8d85bd2fd145d1c2b560bcb66ba');
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('tesseract4android-openmp:4.8.0'));
    final repos = File('android/build.gradle.kts').readAsStringSync();
    expect(repos, contains('includeGroup("com.github.adaptech-cz.Tesseract4Android")'), reason: 'JitPack serves this one library only');
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

  test('dependencies are the allowlist — only http can reach the network', () {
    // A Windows checkout has CRLF line ends; the pattern below expects LF.
    final pubspec = File('pubspec.yaml').readAsStringSync().replaceAll('\r\n', '\n');
    final deps = RegExp(r'^dependencies:\n((?:  .*\n|\s*\n|  #.*\n)*)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    final names = RegExp(r'^  ([a-z_]+):', multiLine: true).allMatches(deps).map((m) => m.group(1)).toSet();
    expect(names, {'flutter', 'cupertino_icons', 'cryptography', 'path_provider', 'flutter_secure_storage', 'lucide_icons_flutter', 'lifetrack_protocol', 'http', 'flutter_zxing', 'image_picker', 'image', 'qr_flutter', 'local_auth', 'archive', 'share_plus', 'url_launcher', 'flutter_local_notifications', 'timezone', 'flutter_timezone', 'file_picker', 'printing'});
    expect(pubspec.contains('google_fonts'), isFalse, reason: 'runtime font download is network egress');
  });

  test('fonts are bundled', () {
    for (final f in ['Poppins-Regular', 'Poppins-Medium', 'Poppins-SemiBold', 'Poppins-Bold']) {
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
