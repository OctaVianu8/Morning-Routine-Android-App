import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../models/habit.dart';
import '../services/app_state.dart';
import '../services/briefing_service.dart';
import '../services/calendar_service.dart';
import '../services/weather_service.dart';
import '../services/tts_service.dart';
import '../widgets/streak_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final habits = s.enabledHabits;

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
          ],
        ),
        const SizedBox(height: 16),
        const StreakCard(),
        if (s.settings.briefingEnabled) ...[
          const SizedBox(height: 8),
          const _BriefingCard(),
        ],
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

/// "Daily briefing" card: weather line, next events and a play button.
class _BriefingCard extends StatefulWidget {
  const _BriefingCard();

  @override
  State<_BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends State<_BriefingCard> with WidgetsBindingObserver {
  late AppState _app;
  WeatherReport? _weather;
  List<DayEvent>? _events; // null = calendar off / no permission
  bool _calendarMissing = false;
  bool _playing = false;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<AppState>();
    final st = context.watch<AppState>().settings;
    final key = '${st.briefingWeather}|${st.cityLat}|${st.cityLon}|${st.briefingCalendar}';
    if (key != _loadedFor) {
      _loadedFor = key;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final st = _app.settings;
      WeatherReport? w;
      if (st.briefingWeather && st.hasCity) {
        w = await WeatherService.instance.today(st.cityLat!, st.cityLon!);
      }
      List<DayEvent>? ev;
      var missing = false;
      if (st.briefingCalendar) {
        if (await CalendarService.instance.hasPermission()) {
          ev = await CalendarService.instance.todayEvents();
        } else {
          missing = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _weather = w;
        _events = ev;
        _calendarMissing = missing;
      });
    } catch (e) {
      debugPrint('Briefing card load failed: $e');
    }
  }

  Future<void> _connect() async {
    await CalendarService.instance.connect(ScaffoldMessenger.of(context));
    if (mounted) await _load();
  }

  Future<void> _play() async {
    if (_playing) return;
    setState(() => _playing = true);
    try {
      await BriefingService.instance.speak(_app);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _stop() => TtsService.instance.stop();

  IconData _icon(int code) {
    if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
    if (code == 2 || code == 3) return Icons.cloud_outlined;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 71 && code <= 77 || code == 85 || code == 86) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm_outlined;
    return Icons.water_drop_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = context.watch<AppState>().settings;
    final w = _weather;

    String weatherLine;
    IconData weatherIcon = Icons.cloud_outlined;
    if (!st.briefingWeather) {
      weatherLine = '';
    } else if (!st.hasCity) {
      weatherLine = 'Set your city in Settings for weather';
    } else if (w == null) {
      weatherLine = 'Weather unavailable';
    } else {
      weatherIcon = _icon(w.code);
      final d = w.description;
      weatherLine = '${w.now.round()}\u00b0 \u00b7 '
          '${d[0].toUpperCase()}${d.substring(1)}'
          '${st.cityLabel.isEmpty ? '' : ' \u00b7 ${st.cityLabel.split(',').first}'}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily briefing', style: tt.titleMedium),
            if (weatherLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(weatherIcon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(weatherLine, style: tt.bodyMedium)),
              ]),
            ],
            if (st.briefingCalendar) ...[
              const SizedBox(height: 8),
              if (_calendarMissing)
                Row(children: [
                  Icon(Icons.event_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Calendar not connected',
                          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                  TextButton(onPressed: _connect, child: const Text('Connect calendar')),
                ])
              else if (_events != null && _events!.isEmpty)
                Row(children: [
                  Icon(Icons.event_available_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Calendar is clear', style: tt.bodyMedium),
                ])
              else if (_events != null)
                for (final e in _events!.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                            e.allDay ? 'All day' : DateFormat.jm().format(e.start),
                            style: tt.bodyMedium?.copyWith(color: cs.primary)),
                      ),
                      Expanded(
                          child: Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium)),
                    ]),
                  ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _playing ? null : _play,
                  icon: _playing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Play briefing'),
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _stop,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
