import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../services/app_state.dart';
import 'alarm_edit_screen.dart';

String formatTime(BuildContext context, int hour, int minute) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));

String repeatSummary(Set<int> days) {
  if (days.isEmpty) return 'Once';
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.every((d) => d <= 5)) return 'Weekdays';
  if (days.length == 2 && days.containsAll({6, 7})) return 'Weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (days.toList()..sort()).map((d) => names[d - 1]).join(', ');
}

String relativeTime(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  final days = mins ~/ (24 * 60);
  final h = (mins % (24 * 60)) ~/ 60;
  final m = mins % 60;
  if (days > 0) return '$days d $h h';
  if (h > 0) return '$h h $m min';
  return '${m < 1 ? 1 : m} min';
}

class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key});

  static Future<void> openEditor(BuildContext context, {AlarmConfig? existing}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AlarmEditScreen(existing: existing),
      ));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final alarms = app.alarms;

    if (alarms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.alarm_add, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text('No alarms yet', style: tt.titleLarge),
            const SizedBox(height: 8),
            Text('Tap + to set your first alarm.\nIt only stops after you do your pushups.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      );
    }

    final now = DateTime.now();
    DateTime? next;
    for (final a in alarms.where((a) => a.enabled)) {
      final t = a.nextOccurrence(now);
      if (next == null || t.isBefore(next)) next = t;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            next == null
                ? 'All alarms are off'
                : 'Rings in ${relativeTime(next.difference(now))}',
            style: tt.titleMedium?.copyWith(color: cs.primary),
          ),
        ),
        for (final a in alarms)
          Dismissible(
            key: ValueKey(a.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  color: cs.errorContainer, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.delete, color: cs.onErrorContainer),
            ),
            onDismissed: (_) {
              app.deleteAlarm(a.id);
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(
                  content: const Text('Alarm deleted'),
                  action: SnackBarAction(label: 'Undo', onPressed: () => app.upsertAlarm(a)),
                ));
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openEditor(context, existing: a),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(formatTime(context, a.hour, a.minute),
                            style: tt.displaySmall?.copyWith(
                                color: a.enabled ? cs.onSurface : cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (a.label.isNotEmpty) a.label,
                            repeatSummary(a.weekdays),
                            '${app.pushupTargetFor(a.id)} pushups',
                          ].join(' · '),
                          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    Switch(
                      value: a.enabled,
                      onChanged: (v) => app.upsertAlarm(a.copyWith(enabled: v)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
