import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes each measured action's frame summary to
/// `build/<name>.frame_summary.json` (from `watchPerformance`).
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        await Directory('build').create(recursive: true);
        for (final e in (data ?? {}).entries) {
          await File('build/${e.key}.frame_summary.json').writeAsString(const JsonEncoder.withIndent('  ').convert(e.value));
        }
      },
    );
