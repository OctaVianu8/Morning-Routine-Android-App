import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_config.dart';
import '../models/app_settings.dart';
import '../models/habit.dart';

/// Single source of truth for persisted app data (alarms, habits, daily
/// completions, settings). Exposed to the widget tree with `provider`.
///
/// Side effects (re-scheduling alarms / reminders) are wired in main.dart via
/// [onAlarmsChanged] and [onHabitsChanged]; screens only call the mutators.
class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;

  static const _kAlarms = 'alarms';
  static const _kHabits = 'habits';
  static const _kSettings = 'settings';
  static const _kDone = 'completions';

  List<AlarmConfig> _alarms = [];
  List<Habit> _habits = [];
  AppSettings _settings = const AppSettings();
  // 'yyyy-MM-dd' -> ids of habits completed that day.
  Map<String, Set<String>> _done = {};

  VoidCallback? onAlarmsChanged;
  VoidCallback? onHabitsChanged;

  List<AlarmConfig> get alarms => List.unmodifiable(_alarms);
  List<Habit> get habits => List.unmodifiable(_habits);
  List<Habit> get enabledHabits => _habits.where((h) => h.enabled).toList();
  AppSettings get settings => _settings;

  static Future<AppState> load() async {
    final s = AppState(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  void _read() {
    try {
      final a = _prefs.getString(_kAlarms);
      if (a != null) {
        _alarms = (jsonDecode(a) as List)
            .map((e) => AlarmConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final h = _prefs.getString(_kHabits);
      _habits = h == null
          ? List.of(Habit.recommended)
          : (jsonDecode(h) as List)
              .map((e) => Habit.fromJson(e as Map<String, dynamic>))
              .toList();
      final st = _prefs.getString(_kSettings);
      if (st != null) {
        _settings = AppSettings.fromJson(jsonDecode(st) as Map<String, dynamic>);
      }
      final d = _prefs.getString(_kDone);
      if (d != null) {
        _done = (jsonDecode(d) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as List).cast<String>().toSet()),
        );
      }
    } catch (e) {
      debugPrint('AppState: corrupt storage, using defaults ($e)');
      if (_habits.isEmpty) _habits = List.of(Habit.recommended);
    }
  }

  // ---- alarms ----

  int newAlarmId() {
    var id = DateTime.now().millisecondsSinceEpoch % 1000000000 + 1;
    while (_alarms.any((a) => a.id == id)) {
      id++;
    }
    return id;
  }

  AlarmConfig? alarmById(int id) {
    for (final a in _alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Insert or replace (matched by id).
  void upsertAlarm(AlarmConfig alarm) {
    final i = _alarms.indexWhere((a) => a.id == alarm.id);
    if (i < 0) {
      _alarms.add(alarm);
    } else {
      _alarms[i] = alarm;
    }
    _alarms.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    _saveAlarms();
  }

  void deleteAlarm(int id) {
    _alarms.removeWhere((a) => a.id == id);
    _saveAlarms();
  }

  void _saveAlarms() {
    _prefs.setString(_kAlarms, jsonEncode(_alarms.map((a) => a.toJson()).toList()));
    notifyListeners();
    onAlarmsChanged?.call();
  }

  /// Pushups required for the given alarm (falls back to the global target).
  int pushupTargetFor(int alarmId) =>
      alarmById(alarmId)?.pushupsOverride ?? _settings.pushupTarget;

  // ---- habits ----

  void upsertHabit(Habit habit) {
    final i = _habits.indexWhere((h) => h.id == habit.id);
    if (i < 0) {
      _habits.add(habit);
    } else {
      _habits[i] = habit;
    }
    _saveHabits();
  }

  void deleteHabit(String id) {
    _habits.removeWhere((h) => h.id == id);
    _saveHabits();
  }

  void reorderHabits(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    _habits.insert(newIndex, _habits.removeAt(oldIndex));
    _saveHabits();
  }

  void _saveHabits() {
    _prefs.setString(_kHabits, jsonEncode(_habits.map((h) => h.toJson()).toList()));
    notifyListeners();
    onHabitsChanged?.call();
  }

  // ---- completions ----

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool isDone(String habitId, [DateTime? day]) =>
      _done[dayKey(day ?? DateTime.now())]?.contains(habitId) ?? false;

  void setDone(String habitId, bool done, [DateTime? day]) {
    final set = _done.putIfAbsent(dayKey(day ?? DateTime.now()), () => <String>{});
    if (done ? !set.add(habitId) : !set.remove(habitId)) return;
    _prefs.setString(
        _kDone, jsonEncode(_done.map((k, v) => MapEntry(k, v.toList()))));
    notifyListeners();
  }

  /// Number of enabled habits done on [day] (default today).
  int doneCount([DateTime? day]) => enabledHabits.where((h) => isDone(h.id, day)).length;

  /// A day counts when every currently-enabled habit was completed.
  bool isPerfectDay(DateTime day) {
    final hs = enabledHabits;
    return hs.isNotEmpty && hs.every((h) => isDone(h.id, day));
  }

  /// Consecutive perfect days ending today (today not yet perfect doesn't break it).
  int get streak {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    var n = 0;
    if (isPerfectDay(day)) n++;
    while (true) {
      day = DateTime(day.year, day.month, day.day - 1);
      if (!isPerfectDay(day)) return n;
      n++;
    }
  }

  // ---- settings ----

  void updateSettings(AppSettings s) {
    _settings = s;
    _prefs.setString(_kSettings, jsonEncode(s.toJson()));
    notifyListeners();
    onAlarmsChanged?.call(); // volume / vibrate are baked into scheduled alarms
  }
}
