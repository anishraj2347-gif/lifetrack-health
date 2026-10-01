// Renders the main screens in dark mode to PNGs for a visual check:
//   flutter test test/tool/dark_screens_test.dart --dart-define=SHOTS=<dir>
// Skipped unless SHOTS is set.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

const out = String.fromEnvironment('SHOTS');

void main() {
  testWidgets('dark screens', skip: out.isEmpty, (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('Poppins');
      for (final f in Directory('fonts').listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      }
      await loader.load();
    });
    late AppServices s;
    await tester.runAsync(() async {
      s = await AppServices.open(
        bytes: InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 5)), remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => DateTime(2026, 10, 1, 10), demoTools: true,
      );
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await s.addSampleRecords();
      await s.setThemeChoice(const String.fromEnvironment('MODE', defaultValue: 'dark'));
    });
    addTearDown(() {
      appearance.value = ThemeMode.system;
      LT.dark = false;
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LifeTrackApp(boot: () async => s)));
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('1-reminders');
    for (final (i, tab) in ['Records', 'Share', 'Me'].indexed) {
      await tester.tap(find.bySemanticsLabel(tab));
      await shot('${i + 2}-${tab.toLowerCase()}');
    }
  });
}
