import 'package:flutter/services.dart';

/// Blanks screenshots, screen recordings and the Recent apps preview while
/// LifeTrack is on screen (Android FLAG_SECURE).
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
      // Not on Android (iOS, web, tests): nothing to set.
    }
  }
}

/// Tests: remembers the last value.
class RecordingScreenPrivacy implements ScreenPrivacy {
  bool? on;
  @override
  Future<void> set(bool on) async => this.on = on;
}
