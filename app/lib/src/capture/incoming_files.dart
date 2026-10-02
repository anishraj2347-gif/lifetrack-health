import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A photo or PDF another app shared to LifeTrack ("Share to LifeTrack" from
/// WhatsApp, Gmail, Files). Held in memory by the platform until the
/// unlocked app takes it; never written to disk in the clear.
typedef IncomingFile = ({String mime, Uint8List bytes});

abstract final class IncomingFiles {
  static const _channel = MethodChannel('lifetrack/incoming');

  /// Ticks when files arrive while the app is open.
  static final arrivals = ValueNotifier<int>(0);
  static bool _listening = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') arrivals.value++;
    });
  }

  /// Everything waiting, once. Empty off Android and under test.
  static Future<List<IncomingFile>> take() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('take') ?? const [];
      return [for (final m in raw) (mime: m['mime']! as String, bytes: m['bytes']! as Uint8List)];
    } on Object {
      return const [];
    }
  }
}
