/// A morning habit shown on the Today checklist.
class Habit {
  const Habit({
    required this.id,
    required this.title,
    this.emoji = '✅',
    this.enabled = true,
    this.reminderMinutes,
  });

  final String id;
  final String title;
  final String emoji;
  final bool enabled;

  /// Daily reminder time as minutes after midnight; null = no reminder.
  final int? reminderMinutes;

  /// The habit that is auto-completed when an alarm is dismissed with pushups.
  static const String pushupsId = 'pushups';

  static const List<Habit> recommended = [
    Habit(id: pushupsId, title: 'Do pushups', emoji: '💪'),
    Habit(id: 'water', title: 'Drink a glass of water', emoji: '💧'),
    Habit(id: 'bed', title: 'Make the bed', emoji: '🛏️'),
    Habit(id: 'yogurt', title: 'Drink yogurt', emoji: '🥛'),
    Habit(id: 'outside', title: 'Go outside for 5 minutes', emoji: '🌤️'),
    Habit(id: 'stretch', title: 'Stretch for 2 minutes', emoji: '🧘', enabled: false),
    Habit(id: 'nophone', title: 'No social media for 30 minutes', emoji: '📵', enabled: false),
  ];

  Habit copyWith({
    String? title,
    String? emoji,
    bool? enabled,
    int? reminderMinutes,
    bool clearReminder = false,
  }) =>
      Habit(
        id: id,
        title: title ?? this.title,
        emoji: emoji ?? this.emoji,
        enabled: enabled ?? this.enabled,
        reminderMinutes:
            clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'enabled': enabled,
        'reminderMinutes': reminderMinutes,
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        title: j['title'] as String,
        emoji: j['emoji'] as String? ?? '✅',
        enabled: j['enabled'] as bool? ?? true,
        reminderMinutes: j['reminderMinutes'] as int?,
      );
}
