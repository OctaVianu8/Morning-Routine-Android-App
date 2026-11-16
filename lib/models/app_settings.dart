class AppSettings {
  const AppSettings({
    this.pushupTarget = 20,
    this.fallbackEnabled = true,
    this.fallbackDelaySec = 60,
    this.mathProblems = 5,
    this.voiceEnabled = true,
    this.countAloud = true,
    this.speakHabitsAfterAlarm = true,
    this.alarmVolume = 1.0,
    this.vibrate = true,
  });

  /// Pushups needed to stop an alarm (1..100).
  final int pushupTarget;

  /// Whether the math-problem escape hatch is offered at all.
  final bool fallbackEnabled;

  /// Seconds of ringing before the escape hatch unlocks.
  final int fallbackDelaySec;

  /// Number of math problems to solve in the escape hatch.
  final int mathProblems;

  /// Master switch for text-to-speech.
  final bool voiceEnabled;

  /// Speak the rep count after each pushup.
  final bool countAloud;

  /// After the alarm is dismissed, read out the remaining habits.
  final bool speakHabitsAfterAlarm;

  /// 0.0..1.0, enforced while the alarm rings.
  final double alarmVolume;
  final bool vibrate;

  AppSettings copyWith({
    int? pushupTarget,
    bool? fallbackEnabled,
    int? fallbackDelaySec,
    int? mathProblems,
    bool? voiceEnabled,
    bool? countAloud,
    bool? speakHabitsAfterAlarm,
    double? alarmVolume,
    bool? vibrate,
  }) =>
      AppSettings(
        pushupTarget: pushupTarget ?? this.pushupTarget,
        fallbackEnabled: fallbackEnabled ?? this.fallbackEnabled,
        fallbackDelaySec: fallbackDelaySec ?? this.fallbackDelaySec,
        mathProblems: mathProblems ?? this.mathProblems,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        countAloud: countAloud ?? this.countAloud,
        speakHabitsAfterAlarm: speakHabitsAfterAlarm ?? this.speakHabitsAfterAlarm,
        alarmVolume: alarmVolume ?? this.alarmVolume,
        vibrate: vibrate ?? this.vibrate,
      );

  Map<String, dynamic> toJson() => {
        'pushupTarget': pushupTarget,
        'fallbackEnabled': fallbackEnabled,
        'fallbackDelaySec': fallbackDelaySec,
        'mathProblems': mathProblems,
        'voiceEnabled': voiceEnabled,
        'countAloud': countAloud,
        'speakHabitsAfterAlarm': speakHabitsAfterAlarm,
        'alarmVolume': alarmVolume,
        'vibrate': vibrate,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        pushupTarget: j['pushupTarget'] as int? ?? 20,
        fallbackEnabled: j['fallbackEnabled'] as bool? ?? true,
        fallbackDelaySec: j['fallbackDelaySec'] as int? ?? 60,
        mathProblems: j['mathProblems'] as int? ?? 5,
        voiceEnabled: j['voiceEnabled'] as bool? ?? true,
        countAloud: j['countAloud'] as bool? ?? true,
        speakHabitsAfterAlarm: j['speakHabitsAfterAlarm'] as bool? ?? true,
        alarmVolume: (j['alarmVolume'] as num?)?.toDouble() ?? 1.0,
        vibrate: j['vibrate'] as bool? ?? true,
      );
}
