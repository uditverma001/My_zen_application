import 'package:flutter/services.dart';

/// Android phone controls for Focus mode (see MainActivity.kt).
/// Every call fails quietly, so the app still works where a control is unavailable.
class FocusLock {
  FocusLock._();

  static const channel = MethodChannel('zen/focus');

  static Future<T?> _call<T>(String method, [Object? argument]) async {
    try {
      return await channel.invokeMethod<T>(method, argument);
    } catch (_) {
      return null;
    }
  }

  /// Pins Zen to the screen. Android asks the user to confirm first.
  static Future<void> startLock() => _call<bool>('startLock');

  static Future<void> stopLock() => _call<bool>('stopLock');

  static Future<bool> isLocked() async => await _call<bool>('isLocked') ?? false;

  static Future<bool> hasDndAccess() async => await _call<bool>('hasDndAccess') ?? false;

  static Future<void> openDndSettings() => _call<bool>('openDndSettings');

  /// Returns whether Do Not Disturb was changed.
  static Future<bool> setDnd(bool on) async => await _call<bool>('setDnd', on) ?? false;
}
