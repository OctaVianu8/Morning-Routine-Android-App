import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/habit.dart';

/// Daily habit reminders as local notifications. Never throws.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (e) {
        debugPrint('ReminderService: timezone fallback to UTC ($e)');
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      _inited = true;
    } catch (e) {
      debugPrint('ReminderService.init failed: $e');
    }
  }

  Future<bool> requestPermissions() async {
    try {
      if (!_inited) await init();
      if (kIsWeb) return false;
      if (Platform.isAndroid) {
        final r = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return r ?? false;
      }
      if (Platform.isIOS) {
        final r = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
        return r ?? false;
      }
    } catch (e) {
      debugPrint('ReminderService.requestPermissions failed: $e');
    }
    return false;
  }

  int _idFor(String habitId) {
    // Stable FNV-1a hash kept in 100000..(2^31-1).
    var h = 0x811c9dc5;
    for (final c in habitId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return 100000 + h % 2000000000;
  }

  Future<void> syncHabits(List<Habit> habits) async {
    try {
      if (!_inited) await init();
      if (!_inited) return;
      await _plugin.cancelAll();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_reminders',
          'Habit reminders',
          channelDescription: 'Daily reminders for your morning habits',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
      final now = tz.TZDateTime.now(tz.local);
      for (final h in habits) {
        final m = h.reminderMinutes;
        if (!h.enabled || m == null) continue;
        try {
          var when = tz.TZDateTime(
              tz.local, now.year, now.month, now.day, m ~/ 60, m % 60);
          if (!when.isAfter(now)) {
            when = tz.TZDateTime(
                tz.local, now.year, now.month, now.day + 1, m ~/ 60, m % 60);
          }
          await _plugin.zonedSchedule(
            id: _idFor(h.id),
            title: '${h.emoji} ${h.title}',
            body: 'Time for your morning habit',
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        } catch (e) {
          debugPrint('ReminderService: schedule ${h.id} failed: $e');
        }
      }
    } catch (e) {
      debugPrint('ReminderService.syncHabits failed: $e');
    }
  }
}
