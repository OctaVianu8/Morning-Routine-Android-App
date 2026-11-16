import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../models/habit.dart';
import '../services/app_state.dart';
import '../services/tts_service.dart';
import 'alarms_screen.dart';
import 'habits_edit_screen.dart';
import 'ring_screen.dart';

String formatMinutes(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _readRoutine(AppState s) {
    final remaining = s.enabledHabits.where((h) => !s.isDone(h.id)).toList();
    if (remaining.isEmpty) {
      TtsService.instance.speak('All habits done. Great job!');
      return;
    }
    final text = 'You have ${remaining.length} '
        '${remaining.length == 1 ? 'habit' : 'habits'} left. '
        '${remaining.map((h) => h.title).join(', ')}.';
    TtsService.instance.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final habits = s.enabledHabits;
    final done = s.doneCount();
    final progress = habits.isEmpty ? 0.0 : done / habits.length;
    final streak = s.streak;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_greeting(now), style: tt.headlineMedium),
                  Text(DateFormat.MMMMEEEEd().format(now),
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Read my routine',
              icon: const Icon(Icons.record_voice_over),
              onPressed: () => _readRoutine(s),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        streak > 0 ? '🔥 $streak-day streak' : 'No streak yet',
                        style: tt.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$done of ${habits.length} done', style: tt.titleSmall),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: progress, minHeight: 10),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _NextAlarmCard(alarms: s.alarms, now: now),
        const SizedBox(height: 16),
        Text('Morning checklist', style: tt.titleMedium),
        const SizedBox(height: 4),
        if (habits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No habits enabled. Tap "Edit habits" to add some.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        for (final h in habits) _HabitTile(habit: h, state: s),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit habits'),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HabitsEditScreen())),
          ),
        ),
      ],
    );
  }
}

class _NextAlarmCard extends StatelessWidget {
  const _NextAlarmCard({required this.alarms, required this.now});
  final List<AlarmConfig> alarms;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    DateTime? next;
    for (final a in alarms.where((a) => a.enabled)) {
      final t = a.nextOccurrence(now);
      if (next == null || t.isBefore(next)) next = t;
    }
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.alarm, size: 32, color: cs.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: next == null
                  ? Text('No alarm set',
                      style: tt.titleMedium?.copyWith(color: cs.onPrimaryContainer))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TimeOfDay.fromDateTime(next).format(context),
                          style: tt.headlineSmall
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                        Text(
                          'in ${_until(next.difference(now))}',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                      ],
                    ),
            ),
            if (next == null)
              FilledButton(
                onPressed: () => AlarmsScreen.openEditor(context),
                child: const Text('Add alarm'),
              ),
          ],
        ),
      ),
    );
  }

  static String _until(Duration d) {
    final mins = (d.inSeconds / 60).ceil();
    final days = mins ~/ (24 * 60);
    final h = (mins % (24 * 60)) ~/ 60;
    final m = mins % 60;
    if (days > 0) return '$days d $h h';
    if (h > 0) return '$h h $m min';
    return '$m min';
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({required this.habit, required this.state});
  final Habit habit;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = state.isDone(habit.id);
    final isPushups = habit.id == Habit.pushupsId;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => state.setDone(habit.id, !done),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Opacity(
                opacity: done ? 0.5 : 1,
                child: Text(habit.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: tt.bodyLarge?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? cs.onSurface.withValues(alpha: 0.5) : null,
                      ),
                    ),
                    if (habit.reminderMinutes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.notifications_none, size: 16),
                          label: Text(formatMinutes(context, habit.reminderMinutes!)),
                        ),
                      ),
                  ],
                ),
              ),
              if (isPushups && !done)
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const RingScreen(alarmId: -1, practice: true))),
                  child: const Text('Start'),
                ),
              Checkbox(
                value: done,
                onChanged: (v) => state.setDone(habit.id, v ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
