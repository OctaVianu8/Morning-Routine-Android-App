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
  final bool afterAlarm;
}

const _closers = [
  'Now move!',
  'Go win the day.',
  'No snoozing through life. Go.',
  'Make it count. Go.',
  'The day will not wait. Go.',
  'Clock is ticking. Go get it.',
];

const _words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
String _word(int n) => n >= 0 && n < _words.length ? _words[n] : '$n';
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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

  // Greeting
  final part = now.hour < 12 ? 'morning' : (now.hour < 18 ? 'afternoon' : 'evening');
  final name = d.userName.trim();
  final greet = name.isEmpty ? 'Good $part!' : 'Good $part, $name!';
  out.add(d.afterAlarm ? '$greet Alarm off, now up and at it.' : greet);

  // Date
  out.add("It's ${DateFormat('EEEE, MMMM d', 'en_US').format(now)}.");

  // Weather
  final w = d.weather;
  if (w != null) {
    final place = d.cityLabel.split(',').first.trim();
    out.add("It's ${_degrees(w.now)} and ${w.description}"
        '${place.isEmpty ? '' : ' in $place'}, '
        'high of ${_num(w.max)}, low of ${_num(w.min)}.');
    final rain = w.rainChance;
    if (rain != null && rain >= 50) {
      out.add('$rain percent chance of rain. Take an umbrella and go anyway.');
    } else if (w.max.round() <= 5) {
      out.add('Dress warmly, no excuses.');
    } else if (w.max.round() >= 30) {
      out.add('It will be hot. Drink plenty of water.');
    }
  }

  // Calendar
  final ev = d.events;
  if (ev != null) {
    if (ev.isEmpty) {
      out.add('Nothing on the calendar. That means no excuses.');
    } else {
      out.add('${_cap(_word(ev.length))} ${ev.length == 1 ? 'thing' : 'things'} on the schedule.');
      final shown = ev.take(8).toList();
      var timed = 0;
      for (var i = 0; i < shown.length; i++) {
        final e = shown[i];
        var s = e.allDay
            ? 'All day: ${e.title}'
            : '${timed++ == 0 ? 'First, ' : 'Then '}${e.title} at ${_spokenTime(e.start)}';
        if (i == shown.length - 1 && ev.length > shown.length) {
          s += ', and ${ev.length - shown.length} more after that';
        }
        out.add('$s.');
      }
    }
  }

  // Habits and streak
  final rem = d.remainingHabits;
  if (rem.isNotEmpty) {
    final list = _joinList(rem.map(_lowerFirst).toList());
    final tail = d.streak > 0
        ? " Get them done and that's day ${d.streak + 1} of your streak."
        : ' Finish all of them today and the streak starts now.';
    out.add('${_cap(_word(rem.length))} ${rem.length == 1 ? 'habit' : 'habits'} left: $list.$tail');
  } else if (d.totalHabits > 0) {
    out.add(d.todayPerfect && d.streak > 1
        ? "All habits done. That's ${_article(d.streak)} ${d.streak} day streak. Outstanding."
        : 'All habits done. Outstanding.');
  }

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

/// "an 8 day streak", "an 11 day streak", "a 7 day streak".
String _article(int n) {
  final lead = n.toString();
  final an = lead.startsWith('8') ||
      n == 11 ||
      n == 18 ||
      (lead.startsWith('11') || lead.startsWith('18')) && lead.length % 3 == 2;
  return an ? 'an' : 'a';
}
