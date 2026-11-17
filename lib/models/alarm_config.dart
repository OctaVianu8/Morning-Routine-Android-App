import 'dart:io' show Platform;

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
    this.smartWakeMinutes = 0,
    this.customSoundPath,
    this.customSoundName,
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

  /// Smart wake window in minutes (0 = off, max 60): a paired watch may ring
  /// the alarm early, never earlier than this long before the set time.
  final int smartWakeMinutes;

  /// Absolute path of an imported audio file (see AlarmSoundStore); overrides
  /// [sound] when set.
  final String? customSoundPath;

  /// Original file name of the custom sound, for display only.
  final String? customSoundName;

  bool get hasCustomSound => customSoundPath != null && customSoundPath!.isNotEmpty;

  static const Map<String, String> alarmSounds = {
    'classic': 'assets/sounds/alarm_classic.wav',
    'siren': 'assets/sounds/alarm_siren.wav',
  };

  String get assetPath => alarmSounds[sound] ?? alarmSounds['classic']!;

  /// Path to hand to the alarm plugin: the custom file when set (in the form
  /// the platform needs, see [deviceAudioPath]), else the built-in asset.
  String get audioPath =>
      hasCustomSound ? deviceAudioPath(customSoundPath!, ios: Platform.isIOS) : assetPath;

  /// The alarm plugin takes an absolute path on Android, but on iOS resolves
  /// anything not starting with `assets/` relative to the Documents directory
  /// (the container UUID can change across updates), so strip the prefix.
  static String deviceAudioPath(String absolutePath, {required bool ios}) {
    if (!ios) return absolutePath;
    const marker = '/Documents/';
    final i = absolutePath.lastIndexOf(marker);
    return i < 0 ? absolutePath : absolutePath.substring(i + marker.length);
  }

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
    int? smartWakeMinutes,
    String? customSoundPath,
    String? customSoundName,
    bool clearCustomSound = false,
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
        smartWakeMinutes: smartWakeMinutes ?? this.smartWakeMinutes,
        customSoundPath:
            clearCustomSound ? null : (customSoundPath ?? this.customSoundPath),
        customSoundName:
            clearCustomSound ? null : (customSoundName ?? this.customSoundName),
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
        'smartWakeMinutes': smartWakeMinutes,
        'customSoundPath': customSoundPath,
        'customSoundName': customSoundName,
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
        smartWakeMinutes: (j['smartWakeMinutes'] as num?)?.toInt() ?? 0,
        customSoundPath: j['customSoundPath'] as String?,
        customSoundName: j['customSoundName'] as String?,
      );
}
