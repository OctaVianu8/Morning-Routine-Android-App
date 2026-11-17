import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'app_state.dart';
import 'calendar_service.dart';
import 'tts_service.dart';
import 'weather_service.dart';

/// Everything the spoken briefing is composed from.
class BriefingData {
  const BriefingData({
    required this.now,
    this.userName = '',
    this.weather,
    this.cityLabel = '',
    this.events,
    this.remainingHabits = const [],
    this.totalHabits = 0,
    this.streak = 0,
    this.todayPerfect = false,
    this.nextAlarm,
    this.afterAlarm = false,
  });

  final DateTime now;
  final String userName;
  final WeatherReport? weather;
  final String cityLabel;

  /// null = calendar disabled or not available.
  final List<DayEvent>? events;
  final List<String> remainingHabits;
  final int totalHabits;
  final int streak;
  final bool todayPerfect;
  final DateTime? nextAlarm;
  final bool afterAlarm;
}

const _closers = [
  'Have a great day.',
  'Make today count.',
  'Go get it.',
  'You have got this.',
  'Enjoy your day.',
  'Make it a good one.',
];

/// Time in a TTS-friendly form: "9 30 AM", "10 AM".
String _spokenTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ap = t.hour < 12 ? 'AM' : 'PM';
  return t.minute == 0 ? '$h $ap' : '$h ${t.minute} $ap';
}

String _num(num v) {
  final r = v.round();
  return r < 0 ? 'minus ${-r}' : '$r';
}

String _degrees(num v) => '${_num(v)} ${v.round().abs() == 1 ? 'degree' : 'degrees'}';

String _joinList(List<String> items) => items.length <= 1
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

int _dayOfYear(DateTime d) => d.difference(DateTime(d.year)).inDays;

/// Pure: turns [d] into sentences meant to be read by text-to-speech.
String composeBriefing(BriefingData d) {
  final now = d.now;
  final out = <String>[];

  // 1. Greeting
  final part = now.hour < 12 ? 'morning' : (now.hour < 18 ? 'afternoon' : 'evening');
  final name = d.userName.trim();
  final greet = name.isEmpty ? 'Good $part.' : 'Good $part, $name.';
  out.add(d.afterAlarm ? 'Alarm off. Nice work. $greet' : greet);

  // 2. Date
  out.add("It's ${DateFormat('EEEE, MMMM d', 'en_US').format(now)}.");

  // 3. Weather
  final w = d.weather;
  if (w != null) {
    final place = d.cityLabel.split(',').first.trim();
    final lead = place.isEmpty ? "It's" : "In $place it's";
    out.add('$lead ${_degrees(w.now)} and ${w.description}, '
        'with a high of ${_num(w.max)} and a low of ${_num(w.min)}.');
    final rain = w.rainChance;
    if (rain != null && rain >= 50) {
      out.add("There's a $rain percent chance of rain, so take an umbrella.");
    } else if (w.max.round() <= 5) {
      out.add('Dress warmly.');
    } else if (w.max.round() >= 30) {
      out.add('It will be hot, drink plenty of water.');
    }
  }

  // 4. Calendar
  final ev = d.events;
  if (ev != null) {
    if (ev.isEmpty) {
      out.add('Your calendar is clear today.');
    } else {
      out.add(ev.length == 1 ? 'You have 1 event today.' : 'You have ${ev.length} events today.');
      final shown = ev.take(4).toList();
      var timed = 0;
      for (var i = 0; i < shown.length; i++) {
        final e = shown[i];
        final last = i == shown.length - 1;
        var s = e.allDay
            ? 'All day: ${e.title}'
            : '${timed++ == 0 ? 'First, ' : 'Then '}${e.title} at ${_spokenTime(e.start)}';
        if (last && ev.length > shown.length) {
          s += ', and ${ev.length - shown.length} more later';
        }
        out.add('$s.');
      }
    }
  }

  // 5. Habits
  final rem = d.remainingHabits;
  if (rem.isNotEmpty) {
    out.add('You have ${rem.length} ${rem.length == 1 ? 'habit' : 'habits'} left: '
        '${_joinList(rem.map(_lowerFirst).toList())}.');
  } else if (d.totalHabits > 0) {
    out.add('All your habits are done.');
  }

  // 6. Streak
  if (rem.isEmpty && d.todayPerfect) {
    out.add(d.streak > 1 ? 'That makes a ${d.streak} day streak.' : 'That starts your streak.');
  } else if (rem.isNotEmpty) {
    out.add(d.streak > 0
        ? 'Finish them to make it day ${d.streak + 1} of your streak.'
        : 'Finish them all to start a streak.');
  }

  // 7. Next alarm
  final na = d.nextAlarm;
  if (na != null) {
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(na.year, na.month, na.day).difference(today).inDays;
    if (days == 1) {
      out.add('Your next alarm is tomorrow at ${_spokenTime(na)}.');
    } else if (days > 1) {
      out.add('Your next alarm is ${DateFormat('EEEE', 'en_US').format(na)} at ${_spokenTime(na)}.');
    }
  }

  // 8. Closer
  out.add(_closers[_dayOfYear(now) % _closers.length]);

  return out.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Gathers live data (weather, calendar, habits) and speaks the briefing.
class BriefingService {
  BriefingService._();
  static final BriefingService instance = BriefingService._();

  static const _budget = Duration(seconds: 7);

  Future<BriefingData> gather(AppState app, {bool afterAlarm = false}) async {
    final st = app.settings;
    final now = DateTime.now();

    Future<WeatherReport?> weather() async {
      if (!st.briefingWeather || !st.hasCity) return null;
      return WeatherService.instance.today(st.cityLat!, st.cityLon!);
    }

    Future<List<DayEvent>?> calendar() async {
      if (!st.briefingCalendar) return null;
      if (!await CalendarService.instance.hasPermission()) return null;
      return CalendarService.instance.todayEvents();
    }

    WeatherReport? w;
    List<DayEvent>? ev;
    try {
      final r = await Future.wait<Object?>([
        weather().catchError((Object _) => null),
        calendar().catchError((Object _) => null),
      ]).timeout(_budget);
      w = r[0] as WeatherReport?;
      ev = r[1] as List<DayEvent>?;
    } catch (e) {
      debugPrint('BriefingService.gather: $e');
    }

    DateTime? next;
    for (final a in app.alarms.where((a) => a.enabled)) {
      final t = a.nextOccurrence(now);
      if (next == null || t.isBefore(next)) next = t;
    }
    final habits = app.enabledHabits;
    return BriefingData(
      now: now,
      userName: st.userName,
      weather: w,
      cityLabel: st.cityLabel,
      events: ev,
      remainingHabits:
          habits.where((h) => !app.isDone(h.id)).map((h) => h.title).toList(),
      totalHabits: habits.length,
      streak: app.streak,
      todayPerfect: app.isPerfectDay(DateTime(now.year, now.month, now.day)),
      nextAlarm: next,
      afterAlarm: afterAlarm,
    );
  }

  Future<String> buildText(AppState app, {bool afterAlarm = false}) async =>
      composeBriefing(await gather(app, afterAlarm: afterAlarm));

  Future<void> speak(AppState app, {bool afterAlarm = false}) async {
    try {
      await TtsService.instance.speak(await buildText(app, afterAlarm: afterAlarm));
    } catch (e) {
      debugPrint('BriefingService.speak failed: $e');
    }
  }

  /// Warms the weather cache; fire and forget.
  void prefetch(AppState app) {
    final st = app.settings;
    if (!st.briefingEnabled || !st.briefingWeather || !st.hasCity) return;
    unawaited(WeatherService.instance
        .today(st.cityLat!, st.cityLon!)
        .then<void>((_) {}, onError: (Object _) {}));
  }
}
