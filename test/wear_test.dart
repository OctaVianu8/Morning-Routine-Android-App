import 'package:flutter_test/flutter_test.dart';
import 'package:morning_glory/models/alarm_config.dart';
import 'package:morning_glory/models/app_settings.dart';
import 'package:morning_glory/screens/settings_screen.dart';
import 'package:morning_glory/services/briefing_service.dart';
import 'package:morning_glory/services/wear_service.dart';

void main() {
  final now = DateTime(2026, 3, 10, 22, 0); // Tuesday evening

  test('AlarmConfig smartWakeMinutes round trip and legacy json', () {
    final a = AlarmConfig(id: 3, hour: 7, minute: 0, smartWakeMinutes: 25);
    expect(AlarmConfig.fromJson(a.toJson()).smartWakeMinutes, 25);
    expect(a.copyWith(smartWakeMinutes: 0).smartWakeMinutes, 0);
    expect(a.copyWith(hour: 8).smartWakeMinutes, 25);
    final legacy = Map<String, dynamic>.from(a.toJson())
      ..remove('smartWakeMinutes');
    expect(AlarmConfig.fromJson(legacy).smartWakeMinutes, 0);
  });

  group('selectWearPlan', () {
    test('soonest enabled smart alarm wins', () {
      final plan = selectWearPlan([
        AlarmConfig(id: 1, hour: 9, minute: 0, smartWakeMinutes: 30),
        AlarmConfig(id: 2, hour: 6, minute: 30, smartWakeMinutes: 20),
        AlarmConfig(id: 3, hour: 5, minute: 0), // soonest but not smart
        AlarmConfig(
          id: 4,
          hour: 5,
          minute: 30,
          smartWakeMinutes: 10,
          enabled: false,
        ),
      ], now);
      expect(plan.alarmId, 2);
      expect(plan.windowMinutes, 20);
      expect(
        plan.alarmTimeMillis,
        DateTime(2026, 3, 11, 6, 30).millisecondsSinceEpoch,
      );
    });

    test('none -> cancel', () {
      expect(selectWearPlan([], now), WearPlan.cancel);
      expect(
        selectWearPlan([
          AlarmConfig(id: 1, hour: 7, minute: 0),
        ], now).windowMinutes,
        0,
      );
    });
  });

  group('keepPulledForwardAlarm', () {
    final next = DateTime(2026, 3, 11, 6, 30);
    final wakeAt = DateTime(2026, 3, 11, 6, 12);
    final ringAt = wakeAt.add(const Duration(seconds: 6));
    EarlyWake wake({int id = 2, DateTime? at}) =>
        EarlyWake(alarmId: id, at: at ?? wakeAt, reason: 'movement');

    test('keeps a freshly pulled-forward alarm', () {
      final t = wakeAt.add(const Duration(seconds: 3));
      expect(
        keepPulledForwardAlarm(
          alarmId: 2,
          existingDateTime: ringAt,
          nextOccurrence: next,
          now: t,
          lastEarlyWake: wake(),
        ),
        isTrue,
      );
      // just after it started ringing (stored time slightly in the past)
      final t2 = wakeAt.add(const Duration(seconds: 90));
      expect(
        keepPulledForwardAlarm(
          alarmId: 2,
          existingDateTime: ringAt,
          nextOccurrence: next,
          now: t2,
          lastEarlyWake: wake(),
        ),
        isTrue,
      );
    });

    test('user edit to a later time still reschedules', () {
      final t = DateTime(2026, 3, 10, 22, 0);
      // existing is later than the new next -> not earlier
      expect(
        keepPulledForwardAlarm(
          alarmId: 2,
          existingDateTime: DateTime(2026, 3, 11, 7, 0),
          nextOccurrence: DateTime(2026, 3, 11, 6, 30),
          now: t,
          lastEarlyWake: null,
        ),
        isFalse,
      );
      // earlier existing but no recent early wake (user moved alarm later)
      expect(
        keepPulledForwardAlarm(
          alarmId: 2,
          existingDateTime: DateTime(2026, 3, 11, 6, 0),
          nextOccurrence: next,
          now: t,
          lastEarlyWake: null,
        ),
        isFalse,
      );
      expect(
        keepPulledForwardAlarm(
          alarmId: 2,
          existingDateTime: DateTime(2026, 3, 11, 6, 0),
          nextOccurrence: next,
          now: t,
          lastEarlyWake: wake(at: wakeAt.subtract(const Duration(hours: 5))),
        ),
        isFalse,
      );
    });

    test(
      'different alarm id, stale stored time, or old wake are not protected',
      () {
        final t = wakeAt.add(const Duration(seconds: 3));
        expect(
          keepPulledForwardAlarm(
            alarmId: 9,
            existingDateTime: ringAt,
            nextOccurrence: next,
            now: t,
            lastEarlyWake: wake(),
          ),
          isFalse,
        );
        final late = wakeAt.add(const Duration(minutes: 5));
        expect(
          keepPulledForwardAlarm(
            alarmId: 2,
            existingDateTime: ringAt,
            nextOccurrence: next,
            now: late,
            lastEarlyWake: wake(),
          ),
          isFalse,
        );
      },
    );
  });

  test('WearStatus.fromMap tolerates missing fields', () {
    final s = WearStatus.fromMap({
      'watchReachable': true,
      'watchName': 'Galaxy Watch',
    });
    expect(s.watchReachable, isTrue);
    expect(s.state, '');
    expect(s.lastEarlyWake, isNull);
    final w = WearStatus.fromMap({
      'state': 'monitoring',
      'epochs': 42,
      'battery': 63,
      'lastEarlyWakeAt': 1000,
      'lastEarlyWakePlannedAt': 1000 + 18 * 60000,
      'lastEarlyWakeAlarmId': 2,
    });
    expect(describeWatchState(w), 'Monitoring, 42 min of data, battery 63%');
    expect(w.lastEarlyWake!.minutesEarly, 18);
  });

  test('briefing mentions an early wake', () {
    final t = composeBriefing(
      BriefingData(now: DateTime(2026, 3, 11, 6, 40), earlyWakeMinutes: 18),
    );
    expect(
      t,
      contains(
        'Your watch caught you in light sleep and woke you 18 minutes early.',
      ),
    );
    expect(
      composeBriefing(BriefingData(now: DateTime(2026, 3, 11, 6, 40))),
      isNot(contains('watch')),
    );
  });

  test('WearService is a silent no-op without a platform', () async {
    await WearService.instance.syncPlan([
      AlarmConfig(id: 1, hour: 7, minute: 0, smartWakeMinutes: 20),
    ]);
    expect(await WearService.instance.ping(), isFalse);
    expect((await WearService.instance.status()).watchReachable, isFalse);
  });

  group('nextOccurrenceAfterEarlyWake', () {
    final alarm = AlarmConfig(
      id: 9,
      hour: 7,
      minute: 0,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
      smartWakeMinutes: 30,
    );
    final planned = DateTime(2026, 11, 17, 7, 0);
    EarlyWake wake(int id) => EarlyWake(
      alarmId: id,
      at: DateTime(2026, 11, 17, 6, 41),
      reason: 'movement',
      plannedAt: planned,
    );

    test('after an early wake the same morning is skipped', () {
      final now = DateTime(
        2026,
        11,
        17,
        6,
        45,
      ); // pushups done, 07:00 still ahead
      expect(
        nextOccurrenceAfterEarlyWake(alarm, now, wake(9)),
        DateTime(2026, 11, 18, 7, 0),
      );
      expect(
        selectWearPlan([alarm], now, wake(9)).alarmTimeMillis,
        DateTime(2026, 11, 18, 7, 0).millisecondsSinceEpoch,
      );
    });

    test('no early wake, another alarm, or an old wake: regular time', () {
      final now = DateTime(2026, 11, 17, 6, 45);
      expect(nextOccurrenceAfterEarlyWake(alarm, now, null), planned);
      expect(nextOccurrenceAfterEarlyWake(alarm, now, wake(8)), planned);
      final nextDay = DateTime(2026, 11, 17, 7, 30);
      expect(
        nextOccurrenceAfterEarlyWake(alarm, nextDay, wake(9)),
        DateTime(2026, 11, 18, 7, 0),
      );
    });
  });

  test('smartWakeDryRun defaults on and round trips', () {
    expect(const AppSettings().smartWakeDryRun, isTrue);
    final off = const AppSettings().copyWith(smartWakeDryRun: false);
    expect(AppSettings.fromJson(off.toJson()).smartWakeDryRun, isFalse);
    final legacy = Map<String, dynamic>.from(const AppSettings().toJson())
      ..remove('smartWakeDryRun');
    expect(AppSettings.fromJson(legacy).smartWakeDryRun, isTrue);
  });

  test('WearPlan equality includes dryRun', () {
    const a = WearPlan(alarmId: 1, alarmTimeMillis: 5, windowMinutes: 20);
    expect(a.withDryRun(true) == a, isFalse);
    expect(a.withDryRun(true), a.withDryRun(true));
    expect(a.withDryRun(true).hashCode, a.withDryRun(true).hashCode);
  });

  group('WearNight', () {
    final alarm = DateTime(2026, 11, 17, 7, 0);
    WearNight night({
      bool dry = true,
      DateTime? woke,
      String reason = 'movement',
    }) => WearNight(
      alarmTimeMillis: alarm.millisecondsSinceEpoch,
      windowMinutes: 30,
      dryRun: dry,
      wokeAt: woke?.millisecondsSinceEpoch ?? 0,
      reason: reason,
    );

    test('fromJson tolerates missing fields', () {
      final n = WearNight.fromJson({
        'alarmTimeMillis': 1000,
        'windowMinutes': 20,
        'dryRun': true,
        'wokeAt': 500,
        'reason': 'movement',
        'trace': '..m',
        'epochs': 3,
        'hrAvailable': true,
      });
      expect(n.dryRun, isTrue);
      expect(n.trace, '..m');
      expect(n.hrAvailable, isTrue);
      final e = WearNight.fromJson({});
      expect(e.alarmTimeMillis, 0);
      expect(e.trace, '');
      expect(e.dryRun, isFalse);
    });

    test('describeNight', () {
      final w = DateTime(2026, 11, 17, 6, 41);
      expect(
        describeNight(night(woke: w)),
        'Would have woken you at 06:41, 19 min early (movement)',
      );
      expect(
        describeNight(night(reason: '')),
        'No light sleep seen in the window',
      );
      expect(
        describeNight(night(dry: false, woke: w, reason: 'movement+hr')),
        'Woke you at 06:41, 19 min early (movement and heart rate)',
      );
      expect(
        describeNight(night(dry: false, reason: '')),
        'Rang at the set time (no light sleep seen)',
      );
      expect(describeNight(night(reason: 'not_worn')), 'Watch was not worn');
      expect(
        describeNight(night(reason: 'send_failed')),
        'Watch could not reach the phone',
      );
    });

    test('summarizeTrace', () {
      expect(summarizeTrace(''), '');
      expect(
        summarizeTrace('..mM.h'),
        '2 of 6 half-minutes with movement, 2 with raised heart rate',
      );
      expect(summarizeTrace('....'), '0 of 4 half-minutes with movement');
    });
  });

  test('WearService history is empty without a platform', () async {
    expect(await WearService.instance.history(), isEmpty);
    await WearService.instance.clearHistory();
  });
}
