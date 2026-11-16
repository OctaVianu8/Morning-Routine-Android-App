import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/alarm_config.dart';
import '../models/app_settings.dart';

/// Thin wrapper over the `alarm` package. Screens never schedule directly;
/// AppState changes trigger [sync] (wired in main.dart).
class AlarmScheduler {
  AlarmScheduler._();
  static final AlarmScheduler instance = AlarmScheduler._();

  bool _inited = false;
  Future<void> _queue = Future.value();

  Future<void> init() async {
    try {
      await Alarm.init();
      _inited = true;
    } catch (e, s) {
      debugPrint('AlarmScheduler.init failed: $e\n$s');
    }
  }

  Future<void> requestPermissions() async {
    try {
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('notification permission failed: $e');
    }
    try {
      if (!await Permission.scheduleExactAlarm.isGranted) {
        await Permission.scheduleExactAlarm.request();
      }
    } catch (e) {
      debugPrint('exact alarm permission failed: $e');
    }
    // The alarm package exposes no full-screen-intent check; on Android 14+
    // USE_FULL_SCREEN_INTENT is granted by default to alarm apps.
  }

  /// Serialised so rapid successive changes never interleave.
  Future<void> sync(List<AlarmConfig> alarms, AppSettings settings) {
    _queue = _queue.then((_) => _sync(alarms, settings)).catchError((Object e) {
      debugPrint('AlarmScheduler.sync failed: $e');
    });
    return _queue;
  }

  Future<void> _sync(List<AlarmConfig> alarms, AppSettings settings) async {
    if (!_inited) await init();
    final now = DateTime.now();
    final wanted = {for (final a in alarms.where((a) => a.enabled)) a.id: a};

    List<AlarmSettings> existing;
    try {
      existing = await Alarm.getAlarms();
    } catch (e) {
      debugPrint('Alarm.getAlarms failed: $e');
      existing = const [];
    }
    // Ask the platform, not just the Dart stream: when the app was launched
    // *by* a ringing alarm the stream may not have emitted yet, and calling
    // Alarm.set / Alarm.stop for that id would silence it.
    final ringing = {...currentRingingIds};
    for (final e in existing) {
      if (!e.dateTime.isAfter(now) && await _isRinging(e.id)) ringing.add(e.id);
    }
    for (final e in existing) {
      if (ringing.contains(e.id) || wanted.containsKey(e.id)) continue;
      try {
        await Alarm.stop(e.id);
      } catch (err) {
        debugPrint('cancel ${e.id} failed: $err');
      }
    }

    for (final a in wanted.values) {
      if (ringing.contains(a.id)) continue;
      try {
        final target = settings.pushupTarget;
        final n = a.pushupsOverride ?? target;
        final next = AlarmSettings(
          id: a.id,
          dateTime: a.nextOccurrence(now),
          assetAudioPath: a.assetPath,
          loopAudio: true,
          vibrate: settings.vibrate,
          volumeSettings: VolumeSettings.fixed(
            volume: settings.alarmVolume,
            volumeEnforced: true,
          ),
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          warningNotificationOnKill: true,
          // Only discards alarms found at boot; keep it generous.
          androidStaleAfter: const Duration(hours: 12),
          notificationSettings: NotificationSettings(
            title: a.label.isEmpty ? 'MorningGlory' : a.label,
            body: 'Do $n pushups to stop the alarm',
            // A swipe must not silence the alarm.
            androidStopAlarmOnDismiss: false,
          ),
        );
        final same = existing.any((e) =>
            e.id == next.id &&
            e.dateTime.isAtSameMomentAs(next.dateTime) &&
            e.assetAudioPath == next.assetAudioPath &&
            e.vibrate == next.vibrate &&
            e.volumeSettings == next.volumeSettings &&
            e.notificationSettings == next.notificationSettings);
        if (same) continue;
        await Alarm.set(alarmSettings: next);
      } catch (e, s) {
        debugPrint('Alarm.set ${a.id} failed: $e\n$s');
      }
    }
  }

  Future<bool> _isRinging(int id) async {
    try {
      return await Alarm.isRinging(id);
    } catch (_) {
      return false;
    }
  }

  /// Ids ringing right now according to the platform (slower than
  /// [currentRingingIds] but correct right after a cold start).
  Future<Set<int>> queryRinging() async {
    final ids = {...currentRingingIds};
    try {
      for (final e in await Alarm.getAlarms()) {
        if (!e.dateTime.isAfter(DateTime.now()) && await _isRinging(e.id)) {
          ids.add(e.id);
        }
      }
    } catch (e) {
      debugPrint('queryRinging failed: $e');
    }
    return ids;
  }

  Future<void> stop(int id) async {
    try {
      await Alarm.stop(id);
    } catch (e) {
      debugPrint('Alarm.stop($id) failed: $e');
    }
  }

  Stream<Set<int>> get ringingIds async* {
    yield currentRingingIds;
    yield* Alarm.ringing.map((s) => s.alarms.map((a) => a.id).toSet());
  }

  Set<int> get currentRingingIds {
    try {
      return Alarm.ringing.value.alarms.map((a) => a.id).toSet();
    } catch (_) {
      return <int>{};
    }
  }
}
