import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes each traced action's frame summary to `build/<name>.timeline_summary.json`.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        for (final e in (data ?? {}).entries) {
          final timeline = driver.Timeline.fromJson(e.value as Map<String, dynamic>);
          await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(e.key, pretty: true, includeSummary: true);
        }
      },
    );
