import 'dart:convert';

import 'focus_lock.dart';
import 'store.dart';

/// Apps besides Phone that can be allowed during focus.
const maxAllowedApps = 5;

/// Suggested on first use, when installed: WhatsApp and Google Pay.
const suggestedApps = ['com.whatsapp', 'com.google.android.apps.nbu.paisa.user'];

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A repeating focus block. Mirrors `Schedule` in FocusRules.kt, which enforces it.
class FocusSchedule {
  const FocusSchedule({required this.days, required this.start, required this.end, this.enabled = true});

  /// ISO weekdays (1 = Monday … 7 = Sunday) on which the block starts.
  final Set<int> days;

  /// Minutes after midnight. An [end] before [start] runs past midnight.
  final int start;
  final int end;
  final bool enabled;

  bool get overnight => end < start;

  factory FocusSchedule.fromJson(Map<String, dynamic> j) => FocusSchedule(
    days: {for (final d in j['days'] as List? ?? const []) (d as num).toInt()},
    start: (j['start'] as num?)?.toInt() ?? 0,
    end: (j['end'] as num?)?.toInt() ?? 0,
    enabled: j['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {'days': (days.toList()..sort()), 'start': start, 'end': end, 'enabled': enabled};

  FocusSchedule copyWith({bool? enabled}) =>
      FocusSchedule(days: days, start: start, end: end, enabled: enabled ?? this.enabled);

  /// Whether this block is running at [now]. Same rules as FocusRules.scheduleWindow.
  bool isActiveAt(DateTime now) {
    if (!enabled || start == end || days.isEmpty) return false;
    final minute = now.hour * 60 + now.minute;
    final today = now.weekday;
    final yesterday = today == 1 ? 7 : today - 1;
    if (!overnight) return days.contains(today) && minute >= start && minute < end;
    return (days.contains(today) && minute >= start) || (days.contains(yesterday) && minute < end);
  }

  String get timeLabel => '${formatMinutes(start)} – ${formatMinutes(end)}${overnight ? ' (next day)' : ''}';

  String get daysLabel {
    final sorted = days.toList()..sort();
    if (sorted.length == 7) return 'Every day';
    if (sorted.join() == '12345') return 'Weekdays';
    if (sorted.join() == '67') return 'Weekends';
    return sorted.map((d) => weekdayShort[d - 1]).join(', ');
  }
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Allowed apps and schedules, saved with the rest of the app's data and mirrored to Android.
class FocusConfig {
  FocusConfig({required this.allowed, required this.schedules});

  final List<String> allowed;
  final List<FocusSchedule> schedules;

  static FocusConfig load(ZenStore store) {
    final allowed = store.setting<List<dynamic>?>('focusAllowed', null);
    final schedules = store.setting<List<dynamic>>('focusSchedules', const []);
    return FocusConfig(
      allowed: [for (final a in allowed ?? const []) a as String],
      schedules: [for (final s in schedules) FocusSchedule.fromJson(Map<String, dynamic>.from(s as Map))],
    );
  }

  /// Whether allowed apps were ever chosen (so suggestions are only applied once).
  static bool hasAllowedApps(ZenStore store) => store.setting<List<dynamic>?>('focusAllowed', null) != null;

  String toNativeJson() => jsonEncode({
    'allowed': allowed,
    'schedules': [for (final s in schedules) s.toJson()],
  });

  /// Saves the config if Android accepts it (it refuses during focus). Returns whether it was saved.
  Future<bool> save(ZenStore store) async {
    if (!await FocusLock.setConfig(toNativeJson())) return false;
    store.setSetting('focusAllowed', allowed);
    store.setSetting('focusSchedules', [for (final s in schedules) s.toJson()]);
    return true;
  }
}
