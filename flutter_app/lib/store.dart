import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A finished breathing or meditation session.
class Session {
  Session({required this.type, required this.seconds, required this.at});

  final String type;
  final int seconds;
  final DateTime at;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    type: j['type'] as String? ?? 'meditate',
    seconds: (j['seconds'] as num?)?.round() ?? 0,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> toJson() => {'type': type, 'seconds': seconds, 'at': at.millisecondsSinceEpoch};
}

class JournalEntry {
  JournalEntry({required this.id, required this.mood, required this.text, required this.at});

  final String id;
  final int mood;
  final String text;
  final DateTime at;

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
    id: j['id'] as String? ?? '',
    mood: (j['mood'] as num?)?.toInt() ?? 3,
    text: j['text'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> toJson() => {'id': id, 'mood': mood, 'text': text, 'at': at.millisecondsSinceEpoch};
}

/// All app data. Lives only on the device, in SharedPreferences.
class ZenStore extends ChangeNotifier {
  ZenStore._(this._prefs, this.sessions, this.journal, this.settings);

  static const _key = 'zen.v1';

  final SharedPreferences _prefs;
  final List<Session> sessions;
  final List<JournalEntry> journal;
  final Map<String, dynamic> settings;

  static Future<ZenStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var sessions = <Session>[];
    var journal = <JournalEntry>[];
    var settings = <String, dynamic>{};
    try {
      final raw = prefs.getString(_key);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        sessions = [for (final s in data['sessions'] as List? ?? const []) Session.fromJson(s as Map<String, dynamic>)];
        journal = [
          for (final e in data['journal'] as List? ?? const []) JournalEntry.fromJson(e as Map<String, dynamic>),
        ];
        settings = Map<String, dynamic>.from(data['prefs'] as Map? ?? const {});
      }
    } catch (_) {
      // Corrupt data: start fresh rather than crash.
    }
    return ZenStore._(prefs, sessions, journal, settings);
  }

  Future<void> _save() => _prefs.setString(
    _key,
    jsonEncode({
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'journal': journal.map((e) => e.toJson()).toList(),
      'prefs': settings,
    }),
  );

  T setting<T>(String key, T fallback) {
    final v = settings[key];
    return v is T ? v : fallback;
  }

  void setSetting(String key, Object value) {
    settings[key] = value;
    _save();
  }

  void addSession(String type, int seconds) {
    sessions.add(Session(type: type, seconds: seconds, at: DateTime.now()));
    _save();
    notifyListeners();
  }

  void addEntry(int mood, String text) {
    final now = DateTime.now();
    journal.add(JournalEntry(id: '${now.microsecondsSinceEpoch}', mood: mood, text: text, at: now));
    _save();
    notifyListeners();
  }

  void deleteEntry(String id) {
    journal.removeWhere((e) => e.id == id);
    _save();
    notifyListeners();
  }

  int get totalMinutes => sessions.fold<int>(0, (sum, s) => sum + s.seconds) ~/ 60;

  Set<DateTime> get practicedDays => {for (final s in sessions) dateOnly(s.at)};

  /// Consecutive days with practice. Not having practiced yet today doesn't break it.
  int get streak {
    final days = practicedDays;
    var d = dateOnly(DateTime.now());
    if (!days.contains(d)) d = DateTime(d.year, d.month, d.day - 1);
    var count = 0;
    while (days.contains(d)) {
      count++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return count;
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
