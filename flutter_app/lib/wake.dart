import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on during practice. Fails quietly where unsupported.
Future<void> keepAwake(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {}
}
