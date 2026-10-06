import 'package:flutter/services.dart';

/// The focus period the phone is in right now, as reported by Android.
class FocusState {
  const FocusState({required this.active, this.since, this.until});

  static const inactive = FocusState(active: false);

  final bool active;
  final DateTime? since;
  final DateTime? until;
}

/// An installed app that can be allowed during focus.
class AppInfo {
  const AppInfo({required this.package, required this.label, this.icon});

  final String package;
  final String label;
  final Uint8List? icon;
}

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

  // App blocker (accessibility service): enforces allowed apps and schedules.

  static Future<bool> guardEnabled() async => await _call<bool>('guardEnabled') ?? false;

  static Future<void> openGuardSettings() => _call<bool>('openGuardSettings');

  static Future<void> openAppInfo() => _call<bool>('openAppInfo');

  /// Sends allowed apps and schedules to Android. Refused (false) while focus is active.
  static Future<bool> setConfig(String json) async => await _call<bool>('setConfig', json) ?? false;

  static Future<bool> startManual(DateTime end) async =>
      await _call<bool>('startManual', end.millisecondsSinceEpoch) ?? false;

  static Future<FocusState> state() async {
    final m = await _call<Map<Object?, Object?>>('state');
    if (m == null || m['active'] != true) return FocusState.inactive;
    DateTime? time(Object? v) => v is int && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return FocusState(active: true, since: time(m['since']), until: time(m['until']));
  }

  static List<AppInfo>? _apps;

  /// Installed apps, loaded once per run.
  static Future<List<AppInfo>> apps() async {
    if (_apps != null) return _apps!;
    final raw = await _call<List<Object?>>('listApps') ?? const [];
    final apps = [
      for (final a in raw.whereType<Map<Object?, Object?>>())
        AppInfo(package: a['package'] as String, label: a['label'] as String, icon: a['icon'] as Uint8List?),
    ];
    if (apps.isNotEmpty) _apps = apps;
    return apps;
  }

  static Future<void> launchApp(String package) => _call<bool>('launchApp', package);

  static Future<void> openDialer() => _call<bool>('openDialer');

  // App pinning: keeps the phone on Zen when the blocker is off.

  /// Pins Zen to the screen. Android asks the user to confirm first.
  static Future<void> startLock() => _call<bool>('startLock');

  static Future<void> stopLock() => _call<bool>('stopLock');

  static Future<bool> isLocked() async => await _call<bool>('isLocked') ?? false;

  // Do Not Disturb.

  static Future<bool> hasDndAccess() async => await _call<bool>('hasDndAccess') ?? false;

  static Future<void> openDndSettings() => _call<bool>('openDndSettings');

  /// Returns whether Do Not Disturb was changed.
  static Future<bool> setDnd(bool on) async => await _call<bool>('setDnd', on) ?? false;
}
