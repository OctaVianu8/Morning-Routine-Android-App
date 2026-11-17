import 'package:flutter_test/flutter_test.dart';
import 'package:morning_glory/models/app_settings.dart';
import 'package:morning_glory/services/briefing_service.dart';
import 'package:morning_glory/services/calendar_service.dart';
import 'package:morning_glory/services/weather_service.dart';

const _weather = WeatherReport(
    now: 4, min: 2, max: 9, code: 3, rainChance: 70);

DayEvent _ev(String t, int h, [int m = 0, bool allDay = false]) =>
    DayEvent(title: t, start: DateTime(2026, 11, 17, h, m), allDay: allDay);

BriefingData _full({bool afterAlarm = false}) => BriefingData(
      now: DateTime(2026, 11, 17, 7, 5),
      userName: 'Octavian',
      weather: _weather,
      cityLabel: 'Bucharest, Romania',
      events: [
        _ev('Holiday', 0, 0, true),
        _ev('Algorithms lecture', 10),
        _ev('Team meeting', 14, 30),
        _ev('Gym', 17),
        _ev('Dinner', 19),
        _ev('Call mom', 21),
      ],
      remainingHabits: ['Drink a glass of water', 'Make the bed', 'Go outside for 5 minutes'],
      totalHabits: 4,
      streak: 7,
      afterAlarm: afterAlarm,
    );

void _clean(String t) {
  expect(t, isNot(contains('null')));
  expect(t, isNot(contains('°')));
  expect(t, isNot(contains('  ')));
  expect(RegExp(r'[\u{1F300}-\u{1FAFF}☀-➿]', unicode: true).hasMatch(t), isFalse);
}

void main() {
  test('full briefing', () {
    final t = composeBriefing(_full());
    _clean(t);
    expect(t, startsWith('Good morning, Octavian!'));
    expect(t, contains("It's Tuesday, November 17."));
    expect(t, contains("It's 4 degrees and overcast in Bucharest, high of 9, low of 2."));
    expect(t, contains('70 percent chance of rain. Take an umbrella and go anyway.'));
    expect(t, contains('Six things on the schedule.'));
    expect(t, contains('All day: Holiday.'));
    expect(t.indexOf('First, Algorithms lecture at 10 AM.'),
        lessThan(t.indexOf('Then Team meeting at 2 30 PM.')));
    expect(t, contains('Then Call mom at 9 PM.'));
    expect(t, contains('Three habits left: drink a glass of water, make the bed and go outside for 5 minutes.'));
    expect(t, contains("Get them done and that's day 8 of your streak."));
    expect(t, isNot(contains('next alarm')));
    expect(t, isNot(contains('Alarm off')));
  });

  test('more than eight events', () {
    final t = composeBriefing(BriefingData(
      now: DateTime(2026, 11, 17, 7),
      events: [for (var i = 0; i < 10; i++) _ev('E$i', 8 + i)],
    ));
    expect(t, contains('Ten things on the schedule.'));
    expect(t, contains('Then E7 at 3 PM, and 2 more after that.'));
    expect(t, isNot(contains('E8')));
  });

  test('after alarm prefix', () {
    expect(composeBriefing(_full(afterAlarm: true)),
        startsWith('Good morning, Octavian! Alarm off, now up and at it.'));
  });

  test('no weather, no calendar, no name', () {
    final t = composeBriefing(BriefingData(
      now: DateTime(2026, 11, 17, 15),
      remainingHabits: ['Make the bed'],
      totalHabits: 1,
    ));
    _clean(t);
    expect(t, startsWith('Good afternoon!'));
    expect(t, isNot(contains('degrees')));
    expect(t, isNot(contains('calendar')));
    expect(t, contains('One habit left: make the bed.'));
    expect(t, contains('Finish all of them today and the streak starts now.'));
  });

  test('calendar clear, advice variants', () {
    BriefingData d(WeatherReport w) =>
        BriefingData(now: DateTime(2026, 7, 1, 9), weather: w, events: const []);
    final cold = composeBriefing(d(const WeatherReport(now: -3, min: -6, max: 2, code: 71)));
    expect(cold, contains('minus 3 degrees'));
    expect(cold, contains('Dress warmly, no excuses.'));
    expect(cold, contains('Nothing on the calendar. That means no excuses.'));
    final hot = composeBriefing(d(const WeatherReport(now: 25, min: 20, max: 33, code: 0)));
    expect(hot, contains('It will be hot. Drink plenty of water.'));
  });

  test('all habits done gives streak sentence', () {
    final t = composeBriefing(BriefingData(
      now: DateTime(2026, 11, 17, 8),
      totalHabits: 3,
      streak: 7,
      todayPerfect: true,
    ));
    _clean(t);
    expect(t, contains("All habits done. That's a 7 day streak. Outstanding."));
  });

  group('WeatherReport.parse', () {
    final json = {
      'latitude': 44.43,
      'current': {'time': '2026-11-17T07:00', 'temperature_2m': 4.2, 'weather_code': 3},
      'daily': {
        'time': ['2026-11-17'],
        'temperature_2m_max': [9.1],
        'temperature_2m_min': [1.8],
        'precipitation_probability_max': [70],
        'weather_code': [61],
      },
    };

    test('realistic', () {
      final w = WeatherReport.parse(json)!;
      expect(w.now, 4.2);
      expect(w.max, 9.1);
      expect(w.min, 1.8);
      expect(w.rainChance, 70);
      expect(w.code, 61);
      expect(w.description, 'rainy');
    });

    test('missing precipitation', () {
      final j = {
        ...json,
        'daily': {
          ...(json['daily']! as Map<String, dynamic>),
          'precipitation_probability_max': [null],
        },
      };
      expect(WeatherReport.parse(j)!.rainChance, isNull);
    });

    test('malformed', () {
      expect(WeatherReport.parse({'current': 5}), isNull);
      expect(WeatherReport.parse({}), isNull);
    });
  });

  test('settings round trip and clearing the city', () {
    const s = AppSettings(
      briefingEnabled: false,
      userName: 'Octavian',
      briefingWeather: false,
      briefingCalendar: false,
      city: 'Bucharest',
      cityLat: 44.43,
      cityLon: 26.1,
      cityLabel: 'Bucharest, Romania',
    );
    final r = AppSettings.fromJson(s.toJson());
    expect(r.briefingEnabled, false);
    expect(r.userName, 'Octavian');
    expect(r.briefingWeather, false);
    expect(r.briefingCalendar, false);
    expect(r.city, 'Bucharest');
    expect(r.cityLat, 44.43);
    expect(r.cityLon, 26.1);
    expect(r.cityLabel, 'Bucharest, Romania');
    final c = r.copyWith(clearCity: true);
    expect(c.hasCity, false);
    expect(c.city, '');
    expect(c.cityLabel, '');
    expect(AppSettings.fromJson(c.toJson()).cityLat, isNull);
    expect(AppSettings.fromJson({}).briefingEnabled, true);
  });
}
