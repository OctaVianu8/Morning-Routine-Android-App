import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/alarm_config.dart';

/// What the phone sends the watch: the alarm to watch for, or a cancel.
@immutable
class WearPlan {
  const WearPlan({
    required this.alarmId,
    required this.alarmTimeMillis,
    required this.windowMinutes,
  });

  static const cancel = WearPlan(alarmId: 0, alarmTimeMillis: 0, windowMinutes: 0);

  final int alarmId;
  final int alarmTimeMillis;
  final int windowMinutes;

  @override
  bool operator ==(Object other) =>
      other is WearPlan &&
      other.alarmId == alarmId &&
      other.alarmTimeMillis == alarmTimeMillis &&
      other.windowMinutes == windowMinutes;

  @override
  int get hashCode => Object.hash(alarmId, alarmTimeMillis, windowMinutes);

  @override
  String toString() => 'WearPlan($alarmId, $alarmTimeMillis, ${windowMinutes}m)';
}

/// Pure: the enabled smart alarm that rings soonest, or [WearPlan.cancel].
WearPlan selectWearPlan(List<AlarmConfig> alarms, DateTime now) {
  WearPlan? best;
  for (final a in alarms) {
    if (!a.enabled || a.smartWakeMinutes <= 0) continue;
    final t = a.nextOccurrence(now).millisecondsSinceEpoch;
    if (best == null || t < best.alarmTimeMillis) {
      best = WearPlan(
        alarmId: a.id,
        alarmTimeMillis: t,
        windowMinutes: a.smartWakeMinutes.clamp(0, 60),
      );
    }
  }
  return best ?? WearPlan.cancel;
}

/// Pure: should [AlarmScheduler] leave a platform alarm alone because the
/// watch pulled it forward? An early trigger re-arms the plugin's stored alarm
/// to "now + 6 s", which is *earlier* than the next regular occurrence; a naive
/// sync would put it back to the set time just as it starts ringing. A plain
/// user edit to a later time must still reschedule, so protection applies only
/// when the native listener recorded an early wake for this very alarm within
/// the last 2 minutes and the stored time is in the future or <2 min past.
bool keepPulledForwardAlarm({
  required int alarmId,
  required DateTime existingDateTime,
  required DateTime nextOccurrence,
  required DateTime now,
  required EarlyWake? lastEarlyWake,
}) {
  if (!existingDateTime.isBefore(nextOccurrence)) return false;
  if (existingDateTime.isBefore(now.subtract(const Duration(minutes: 2)))) return false;
  final w = lastEarlyWake;
  if (w == null || w.alarmId != alarmId || w.at == null) return false;
  final age = now.difference(w.at!);
  return age >= -const Duration(minutes: 1) && age <= const Duration(minutes: 2);
}

@immutable
class EarlyWake {
  const EarlyWake({
    required this.alarmId,
    required this.at,
    required this.reason,
    this.plannedAt,
  });
  final int alarmId;
  final DateTime? at;
  final String reason;

  /// The time the alarm was originally set for.
  final DateTime? plannedAt;

  /// Whole minutes between the early wake and the set time, if known.
  int? get minutesEarly => (at == null || plannedAt == null)
      ? null
      : (plannedAt!.difference(at!).inSeconds / 60).round().clamp(0, 60);
}

/// Latest picture of the watch link; every field is safe to read on error.
@immutable
class WearStatus {
  const WearStatus({
    this.watchReachable = false,
    this.watchName = '',
    this.state = '',
    this.alarmId = 0,
    this.updatedAt,
    this.battery = 0,
    this.hrAvailable = false,
    this.epochs = 0,
    this.wokeAt,
    this.reason = '',
    this.lastEarlyWakeAt,
    this.lastEarlyWakeReason = '',
    this.lastEarlyWakeAlarmId = 0,
    this.lastEarlyWakePlannedAt,
  });

  final bool watchReachable;
  final String watchName;

  /// idle|scheduled|monitoring|woke|finished|no_permission, or '' if unknown.
  final String state;
  final int alarmId;
  final DateTime? updatedAt;
  final int battery;
  final bool hrAvailable;
  final int epochs;
  final DateTime? wokeAt;
  final String reason;
  final DateTime? lastEarlyWakeAt;
  final String lastEarlyWakeReason;
  final int lastEarlyWakeAlarmId;
  final DateTime? lastEarlyWakePlannedAt;

  bool get hasWatchStatus => state.isNotEmpty;

  EarlyWake? get lastEarlyWake => lastEarlyWakeAt == null
      ? null
      : EarlyWake(
          alarmId: lastEarlyWakeAlarmId,
          at: lastEarlyWakeAt,
          reason: lastEarlyWakeReason,
          plannedAt: lastEarlyWakePlannedAt,
        );

  static DateTime? _ms(Object? v) {
    final n = v is num ? v.toInt() : 0;
    return n > 0 ? DateTime.fromMillisecondsSinceEpoch(n) : null;
  }

  factory WearStatus.fromMap(Map<Object?, Object?> m) => WearStatus(
        watchReachable: m['watchReachable'] == true,
        watchName: (m['watchName'] as String?) ?? '',
        state: (m['state'] as String?) ?? '',
        alarmId: (m['alarmId'] as num?)?.toInt() ?? 0,
        updatedAt: _ms(m['updatedAt']),
        battery: (m['battery'] as num?)?.toInt() ?? 0,
        hrAvailable: m['hrAvailable'] == true,
        epochs: (m['epochs'] as num?)?.toInt() ?? 0,
        wokeAt: _ms(m['wokeAt']),
        reason: (m['reason'] as String?) ?? '',
        lastEarlyWakeAt: _ms(m['lastEarlyWakeAt']),
        lastEarlyWakeReason: (m['lastEarlyWakeReason'] as String?) ?? '',
        lastEarlyWakeAlarmId: (m['lastEarlyWakeAlarmId'] as num?)?.toInt() ?? 0,
        lastEarlyWakePlannedAt: _ms(m['lastEarlyWakePlannedAt']),
      );
}

/// Wear OS companion link. Android only; everywhere else, and whenever the
/// platform side is missing (unit tests), every call is a silent no-op.
class WearService {
  WearService._();
  static final WearService instance = WearService._();

  static const _channel = MethodChannel('morning_glory/wear');

  WearPlan? _lastSent;

  bool get _supported {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncPlan(List<AlarmConfig> alarms) async {
    if (!_supported) return;
    final plan = selectWearPlan(alarms, DateTime.now());
    if (plan == _lastSent) return;
    try {
      final ok = await _channel.invokeMethod<bool>('syncPlan', {
        'alarmId': plan.alarmId,
        'alarmTimeMillis': plan.alarmTimeMillis,
        'windowMinutes': plan.windowMinutes,
      });
      // Only remember a delivered plan so a failed send is retried next sync.
      if (ok == true) _lastSent = plan;
    } on MissingPluginException {
      // no platform side (tests)
    } catch (e) {
      debugPrint('WearService.syncPlan failed: $e');
    }
  }

  Future<bool> ping() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('ping') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<WearStatus> status() async {
    if (!_supported) return const WearStatus();
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      return m == null ? const WearStatus() : WearStatus.fromMap(m);
    } catch (_) {
      return const WearStatus();
    }
  }

  /// Cheap local read of the last early wake (no Play services round trip).
  Future<EarlyWake?> lastEarlyWake() async {
    if (!_supported) return null;
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('lastEarlyWake');
      return m == null ? null : WearStatus.fromMap(m).lastEarlyWake;
    } catch (_) {
      return null;
    }
  }
}
