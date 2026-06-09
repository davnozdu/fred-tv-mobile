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

  /// Keeps the screen/device awake (FLAG_KEEP_SCREEN_ON) while [on] is true so
  /// the TV box does not go to sleep during playback.
  static Future<void> setKeepScreenOn(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// Whether the "display over other apps" (SYSTEM_ALERT_WINDOW) permission is
  /// granted — required so the boot receiver can launch the app on Android 12+.
  static Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final v = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen to grant the overlay permission.
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  /// Whether an app with [package] is installed on the device.
  static Future<bool> isPackageInstalled(String package) async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _channel.invokeMethod<bool>(
        'isPackageInstalled',
        {'package': package},
      );
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
