/// A user-configured alarm. Stored as JSON; scheduling is done by AlarmScheduler.
class AlarmConfig {
  AlarmConfig({
    required this.id,
    required this.hour,
    required this.minute,
    Set<int>? weekdays,
    this.enabled = true,
    this.label = '',
    this.pushupsOverride,
    this.sound = 'classic',
  }) : weekdays = weekdays ?? <int>{};

  /// Positive, stable, < 2^31 (used as the platform alarm id).
  final int id;
  final int hour;
  final int minute;

  /// DateTime.monday(1)..DateTime.sunday(7). Empty = ring once, then disable.
  final Set<int> weekdays;
  final bool enabled;
  final String label;

  /// Pushups required for this alarm; null = use AppSettings.pushupTarget.
  final int? pushupsOverride;

  /// Key into [alarmSounds].
  final String sound;

  static const Map<String, String> alarmSounds = {
    'classic': 'assets/sounds/alarm_classic.wav',
    'siren': 'assets/sounds/alarm_siren.wav',
  };

  String get assetPath => alarmSounds[sound] ?? alarmSounds['classic']!;
  bool get repeats => weekdays.isNotEmpty;

  /// Next time this alarm should ring strictly after [now].
  DateTime nextOccurrence(DateTime now) {
    var t = DateTime(now.year, now.month, now.day, hour, minute);
    for (var i = 0; i < 8; i++) {
      if (t.isAfter(now) && (weekdays.isEmpty || weekdays.contains(t.weekday))) {
        return t;
      }
      // Re-normalise through the constructor so DST shifts keep the wall time.
      t = DateTime(t.year, t.month, t.day + 1, hour, minute);
    }
    return t;
  }

  AlarmConfig copyWith({
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
    String? label,
    int? pushupsOverride,
    bool clearPushupsOverride = false,
    String? sound,
  }) =>
      AlarmConfig(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
        label: label ?? this.label,
        pushupsOverride:
            clearPushupsOverride ? null : (pushupsOverride ?? this.pushupsOverride),
        sound: sound ?? this.sound,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays.toList()..sort(),
        'enabled': enabled,
        'label': label,
        'pushupsOverride': pushupsOverride,
        'sound': sound,
      };

  factory AlarmConfig.fromJson(Map<String, dynamic> j) => AlarmConfig(
        id: j['id'] as int,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        weekdays: ((j['weekdays'] as List?) ?? const []).cast<int>().toSet(),
        enabled: j['enabled'] as bool? ?? true,
        label: j['label'] as String? ?? '',
        pushupsOverride: j['pushupsOverride'] as int?,
        sound: j['sound'] as String? ?? 'classic',
      );
}
