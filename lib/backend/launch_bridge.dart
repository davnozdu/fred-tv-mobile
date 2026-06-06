import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the native boot receiver.
/// - [launchedFromBoot] tells us if this process was started by the device
///   boot (so we only auto-play for real reboots, not normal app opens).
/// - [setAutostartEnabled] mirrors the autostart toggle into native
///   SharedPreferences so the boot receiver knows whether to launch the app.
class LaunchBridge {
  static const _channel = MethodChannel('cz.smotrim.player/launch');

  static Future<bool> launchedFromBoot() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _channel.invokeMethod<bool>('launchedFromBoot');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutostartEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setAutostart', {'enabled': enabled});
    } catch (_) {}
  }
}
