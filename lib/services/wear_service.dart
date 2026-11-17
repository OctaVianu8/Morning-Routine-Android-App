import 'dart:convert';
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
    this.dryRun = false,
  });

  static const cancel = WearPlan(
    alarmId: 0,
    alarmTimeMillis: 0,
    windowMinutes: 0,
  );

  /// The watch only records when it would wake you; it never rings early.
  final bool dryRun;

  WearPlan withDryRun(bool v) => WearPlan(
    alarmId: alarmId,
    alarmTimeMillis: alarmTimeMillis,
    windowMinutes: windowMinutes,
    dryRun: v,
  );

  final int alarmId;
  final int alarmTimeMillis;
  final int windowMinutes;

  @override
  bool operator ==(Object other) =>
      other is WearPlan &&
      other.alarmId == alarmId &&
      other.alarmTimeMillis == alarmTimeMillis &&
      other.windowMinutes == windowMinutes &&
      other.dryRun == dryRun;

  @override
  int get hashCode =>
      Object.hash(alarmId, alarmTimeMillis, windowMinutes, dryRun);

  @override
  String toString() =>
      'WearPlan($alarmId, $alarmTimeMillis, ${windowMinutes}m${dryRun ? ', dry run' : ''})';
}

/// Pure: the enabled smart alarm that rings soonest, or [WearPlan.cancel].
WearPlan selectWearPlan(
  List<AlarmConfig> alarms,
  DateTime now, [
  EarlyWake? earlyWake,
]) {
  WearPlan? best;
  for (final a in alarms) {
    if (!a.enabled || a.smartWakeMinutes <= 0) continue;
    final t = nextOccurrenceAfterEarlyWake(
      a,
      now,
      earlyWake,
    ).millisecondsSinceEpoch;
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

/// Pure: when an alarm should ring next, given that the watch may already have
/// rung it early today. After an early wake the regular time is still in the
/// future, so a plain `nextOccurrence(now)` would ring the same alarm a second
/// time a few minutes after the pushups; skip to the occurrence after it.
DateTime nextOccurrenceAfterEarlyWake(
  AlarmConfig a,
  DateTime now,
  EarlyWake? w,
) {
  final planned = w?.plannedAt;
  final at = w?.at;
  if (w != null &&
      w.alarmId == a.id &&
      planned != null &&
      at != null &&
      now.isBefore(planned) &&
      !at.isAfter(now.add(const Duration(minutes: 1))) &&
      planned.difference(at) <= const Duration(minutes: 62)) {
    return a.nextOccurrence(planned);
  }
  return a.nextOccurrence(now);
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
  if (existingDateTime.isBefore(now.subtract(const Duration(minutes: 2)))) {
    return false;
  }
  final w = lastEarlyWake;
  if (w == null || w.alarmId != alarmId || w.at == null) return false;
  final age = now.difference(w.at!);
  return age >= -const Duration(minutes: 1) &&
      age <= const Duration(minutes: 2);
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

/// One recorded night from the watch (see `/morningglory/status`).
@immutable
class WearNight {
  const WearNight({
    required this.alarmTimeMillis,
    this.windowMinutes = 0,
    this.dryRun = false,
    this.wokeAt = 0,
    this.reason = '',
    this.trace = '',
    this.epochs = 0,
    this.hrAvailable = false,
  });

  final int alarmTimeMillis;
  final int windowMinutes;
  final bool dryRun;

  /// Millis the watch woke (or would have woken) you; 0 = never.
  final int wokeAt;
  final String reason;

  /// One char per 30 s epoch: '.' still, 'm' movement, 'h' raised HR, 'M' both.
  final String trace;
  final int epochs;
  final bool hrAvailable;

  DateTime get alarmTime =>
      DateTime.fromMillisecondsSinceEpoch(alarmTimeMillis);
  DateTime? get wokeTime =>
      wokeAt > 0 ? DateTime.fromMillisecondsSinceEpoch(wokeAt) : null;

  factory WearNight.fromJson(Map<String, dynamic> j) => WearNight(
    alarmTimeMillis: (j['alarmTimeMillis'] as num?)?.toInt() ?? 0,
    windowMinutes: (j['windowMinutes'] as num?)?.toInt() ?? 0,
    dryRun: j['dryRun'] == true,
    wokeAt: (j['wokeAt'] as num?)?.toInt() ?? 0,
    reason: (j['reason'] as String?) ?? '',
    trace: (j['trace'] as String?) ?? '',
    epochs: (j['epochs'] as num?)?.toInt() ?? 0,
    hrAvailable: j['hrAvailable'] == true,
  );
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Pure: one-line outcome of a recorded night.
String describeNight(WearNight n) {
  if (n.reason == 'not_worn') return 'Watch was not worn';
  if (n.reason == 'send_failed') return 'Watch could not reach the phone';
  final woke = n.wokeTime;
  if (woke == null) {
    return n.dryRun
        ? 'No light sleep seen in the window'
        : 'Rang at the set time (no light sleep seen)';
  }
  final early = ((n.alarmTimeMillis - n.wokeAt) / 60000).round().clamp(0, 60);
  final why = switch (n.reason) {
    'movement' => 'movement',
    'movement+hr' => 'movement and heart rate',
    _ => '',
  };
  final tail =
      '${_hhmm(woke)}, $early min early${why.isEmpty ? '' : ' ($why)'}';
  return n.dryRun ? 'Would have woken you at $tail' : 'Woke you at $tail';
}

/// Pure: e.g. "8 of 60 half-minutes with movement" (+ raised heart rate).
String summarizeTrace(String trace) {
  if (trace.isEmpty) return '';
  var move = 0, hr = 0;
  for (final c in trace.split('')) {
    if (c == 'm' || c == 'M') move++;
    if (c == 'h' || c == 'M') hr++;
  }
  final base = '$move of ${trace.length} half-minutes with movement';
  return hr > 0 ? '$base, $hr with raised heart rate' : base;
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

  Future<void> syncPlan(List<AlarmConfig> alarms, {bool dryRun = false}) async {
    if (!_supported) return;
    final plan = selectWearPlan(
      alarms,
      DateTime.now(),
      await lastEarlyWake(),
    ).withDryRun(dryRun);
    if (plan == _lastSent) return;
    try {
      final ok = await _channel.invokeMethod<bool>('syncPlan', {
        'alarmId': plan.alarmId,
        'alarmTimeMillis': plan.alarmTimeMillis,
        'windowMinutes': plan.windowMinutes,
        'dryRun': plan.dryRun,
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
      final m = await _channel.invokeMethod<Map<Object?, Object?>>(
        'lastEarlyWake',
      );
      return m == null ? null : WearStatus.fromMap(m).lastEarlyWake;
    } catch (_) {
      return null;
    }
  }

  /// Recorded nights from the watch, newest first.
  Future<List<WearNight>> history() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('history');
      if (raw == null || raw.isEmpty) return const [];
      final list =
          (jsonDecode(raw) as List)
              .whereType<Map<String, dynamic>>()
              .map(WearNight.fromJson)
              .toList()
            ..sort((a, b) => b.alarmTimeMillis.compareTo(a.alarmTimeMillis));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearHistory() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clearHistory');
    } catch (_) {}
  }
}
