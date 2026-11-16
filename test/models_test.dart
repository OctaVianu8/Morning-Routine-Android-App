import 'package:flutter_test/flutter_test.dart';
import 'package:morning_glory/models/alarm_config.dart';
import 'package:morning_glory/models/app_settings.dart';
import 'package:morning_glory/models/habit.dart';
import 'package:morning_glory/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AlarmConfig.nextOccurrence', () {
    // 2026-11-16 is a Monday.
    final monday8 = DateTime(2026, 11, 16, 8, 0);

    test('one-shot later today', () {
      final a = AlarmConfig(id: 1, hour: 9, minute: 30);
      expect(a.nextOccurrence(monday8), DateTime(2026, 11, 16, 9, 30));
    });

    test('one-shot already passed rolls to tomorrow', () {
      final a = AlarmConfig(id: 1, hour: 7, minute: 0);
      expect(a.nextOccurrence(monday8), DateTime(2026, 11, 17, 7, 0));
    });

    test('exactly now is not "after now"', () {
      final a = AlarmConfig(id: 1, hour: 8, minute: 0);
      expect(a.nextOccurrence(monday8), DateTime(2026, 11, 17, 8, 0));
    });

    test('repeating skips non-selected weekdays', () {
      final a = AlarmConfig(
          id: 1, hour: 7, minute: 0, weekdays: {DateTime.wednesday, DateTime.friday});
      expect(a.nextOccurrence(monday8), DateTime(2026, 11, 18, 7, 0));
    });

    test('same weekday already passed wraps a full week', () {
      final a = AlarmConfig(id: 1, hour: 7, minute: 0, weekdays: {DateTime.monday});
      expect(a.nextOccurrence(monday8), DateTime(2026, 11, 23, 7, 0));
    });
  });

  test('models survive a JSON round trip', () {
    final a = AlarmConfig(
        id: 7, hour: 6, minute: 5, weekdays: {1, 3}, label: 'Gym', pushupsOverride: 30, sound: 'siren');
    final a2 = AlarmConfig.fromJson(a.toJson());
    expect([a2.id, a2.hour, a2.minute, a2.weekdays, a2.label, a2.pushupsOverride, a2.sound],
        [7, 6, 5, {1, 3}, 'Gym', 30, 'siren']);

    const h = Habit(id: 'x', title: 'T', emoji: '🙂', reminderMinutes: 450);
    expect(Habit.fromJson(h.toJson()).reminderMinutes, 450);
    expect(h.copyWith(clearReminder: true).reminderMinutes, isNull);

    const s = AppSettings(pushupTarget: 33, fallbackEnabled: false);
    final s2 = AppSettings.fromJson(s.toJson());
    expect([s2.pushupTarget, s2.fallbackEnabled], [33, false]);
  });

  group('AppState', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts with recommended habits and persists changes', () async {
      final s = await AppState.load();
      expect(s.habits.map((h) => h.id), contains(Habit.pushupsId));

      s.upsertAlarm(AlarmConfig(id: s.newAlarmId(), hour: 7, minute: 0, pushupsOverride: 12));
      s.updateSettings(s.settings.copyWith(pushupTarget: 25));
      s.setDone(Habit.pushupsId, true);

      final reloaded = await AppState.load();
      expect(reloaded.alarms, hasLength(1));
      expect(reloaded.pushupTargetFor(reloaded.alarms.first.id), 12);
      expect(reloaded.pushupTargetFor(-1), 25);
      expect(reloaded.isDone(Habit.pushupsId), isTrue);
    });

    test('streak counts consecutive perfect days', () async {
      final s = await AppState.load();
      final now = DateTime.now();
      DateTime ago(int d) => DateTime(now.year, now.month, now.day - d);
      expect(s.streak, 0);
      for (final d in [1, 2]) {
        for (final h in s.enabledHabits) {
          s.setDone(h.id, true, ago(d));
        }
      }
      expect(s.streak, 2); // today unfinished doesn't break the streak
      for (final h in s.enabledHabits) {
        s.setDone(h.id, true);
      }
      expect(s.streak, 3);
    });

    test('alarm mutations fire the reschedule hook', () async {
      final s = await AppState.load();
      var calls = 0;
      s.onAlarmsChanged = () => calls++;
      final a = AlarmConfig(id: 5, hour: 6, minute: 0);
      s.upsertAlarm(a);
      s.upsertAlarm(a.copyWith(enabled: false));
      s.deleteAlarm(5);
      expect(calls, 3);
      expect(s.alarms, isEmpty);
    });
  });
}
