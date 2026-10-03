import 'package:flutter/services.dart';

/// Screenshots, screen recordings and the Recent apps preview come out
/// blank while LT Clinic is on screen (Android FLAG_SECURE).
abstract interface class ScreenPrivacy {
  Future<void> set(bool on);
}

class PlatformScreenPrivacy implements ScreenPrivacy {
  static const _channel = MethodChannel('lifetrack/screen_privacy');

  @override
  Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('set', on);
    } on Object {
      // Not on Android (browser, tests): nothing to set.
    }
  }
}

/// Tests: remembers the last value.
class RecordingScreenPrivacy implements ScreenPrivacy {
  bool? on;
  @override
  Future<void> set(bool on) async => this.on = on;
}
