import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart';
import '../services/app_state.dart';
import '../services/reminder_service.dart';
import 'today_screen.dart' show formatMinutes;

class HabitsEditScreen extends StatelessWidget {
  const HabitsEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final habits = s.habits;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit habits')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add habit',
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: habits.length,
        onReorderItem: (o, n) => s.reorderHabits(o, n > o ? n + 1 : n),
        itemBuilder: (context, i) {
          final h = habits[i];
          return ListTile(
            key: ValueKey(h.id),
            leading: Text(h.emoji, style: const TextStyle(fontSize: 26)),
            title: Text(h.title),
            subtitle: h.reminderMinutes == null
                ? null
                : Text('Reminder ${formatMinutes(context, h.reminderMinutes!)}'),
            onTap: () => _edit(context, h),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: h.enabled,
                  onChanged: (v) => s.upsertHabit(h.copyWith(enabled: v)),
                ),
                const SizedBox(width: 8),
                ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, Habit? existing) async {
    final s = context.read<AppState>();
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HabitSheet(habit: existing),
    );
    if (result == null) return;
    if (result.delete && existing != null) {
      s.deleteHabit(existing.id);
      return;
    }
    final h = result.habit!;
    final firstReminder = h.reminderMinutes != null &&
        (existing == null || existing.reminderMinutes == null);
    s.upsertHabit(h);
    if (firstReminder) ReminderService.instance.requestPermissions();
  }
}

class _EditResult {
  _EditResult.save(Habit this.habit) : delete = false;
  _EditResult.remove()
      : habit = null,
        delete = true;
  final Habit? habit;
  final bool delete;
}

class _HabitSheet extends StatefulWidget {
  const _HabitSheet({this.habit});
  final Habit? habit;

  @override
  State<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<_HabitSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.habit?.title ?? '');
  late final TextEditingController _emoji =
      TextEditingController(text: widget.habit?.emoji ?? '✅');
  int? _minutes;

  @override
  void initState() {
    super.initState();
    _minutes = widget.habit?.reminderMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final m = _minutes ?? 7 * 60;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t != null) setState(() => _minutes = t.hour * 60 + t.minute);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final emoji = _emoji.text.trim().isEmpty ? '✅' : _emoji.text.trim();
    final base = widget.habit ??
        Habit(id: 'custom_${DateTime.now().millisecondsSinceEpoch}', title: title);
    var h = base.copyWith(title: title, emoji: emoji);
    h = _minutes == null
        ? h.copyWith(clearReminder: true)
        : h.copyWith(reminderMinutes: _minutes);
    Navigator.pop(context, _EditResult.save(h));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.habit;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(existing == null ? 'New habit' : 'Edit habit',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _emoji,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                        labelText: 'Emoji', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _title,
                    autofocus: existing == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Title', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_none),
                    label: Text(_minutes == null
                        ? 'Set reminder'
                        : 'Reminder ${formatMinutes(context, _minutes!)}'),
                    onPressed: _pickTime,
                  ),
                ),
                if (_minutes != null)
                  TextButton(
                    onPressed: () => setState(() => _minutes = null),
                    child: const Text('No reminder'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (existing != null && existing.id != Habit.pushupsId)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => Navigator.pop(context, _EditResult.remove()),
                  ),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
