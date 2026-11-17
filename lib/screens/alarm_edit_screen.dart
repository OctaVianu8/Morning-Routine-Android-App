import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../services/app_state.dart';
import '../services/wear_service.dart';
import 'alarms_screen.dart';

class AlarmEditScreen extends StatefulWidget {
  const AlarmEditScreen({super.key, this.existing});
  final AlarmConfig? existing;

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late TimeOfDay _time;
  late Set<int> _days;
  late final TextEditingController _label;
  late String _sound;
  late bool _useDefault;
  late int _pushups;
  late int _smart;
  bool _watchReachable = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final app = context.read<AppState>();
    _time = e != null
        ? TimeOfDay(hour: e.hour, minute: e.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _days = {...?e?.weekdays};
    _label = TextEditingController(text: e?.label ?? '');
    _sound = e?.sound ?? 'classic';
    _useDefault = e?.pushupsOverride == null;
    _pushups = e?.pushupsOverride ?? app.settings.pushupTarget;
    _smart = (e?.smartWakeMinutes ?? 0).clamp(0, 60);
    _checkWatch();
  }

  Future<void> _checkWatch() async {
    final st = await WearService.instance.status();
    if (!mounted) return;
    // Only show the hint when the platform really answered "no watch".
    setState(() => _watchReachable = st.watchReachable);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  void _save() {
    final app = context.read<AppState>();
    final e = widget.existing;
    final alarm = AlarmConfig(
      id: e?.id ?? app.newAlarmId(),
      hour: _time.hour,
      minute: _time.minute,
      weekdays: _days,
      enabled: true,
      label: _label.text.trim(),
      pushupsOverride: _useDefault ? null : _pushups,
      sound: _sound,
      smartWakeMinutes: _smart,
    );
    app.upsertAlarm(alarm);
    final rel = relativeTime(alarm.nextOccurrence(DateTime.now()).difference(DateTime.now()));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Alarm set for $rel from now')));
    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<AppState>().deleteAlarm(widget.existing!.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final defaultN = context.watch<AppState>().settings.pushupTarget;
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New alarm' : 'Edit alarm'),
        actions: [
          if (widget.existing != null)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(_time.format(context),
                  style: tt.displayLarge?.copyWith(color: cs.primary)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Repeat', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (var d = DateTime.monday; d <= DateTime.sunday; d++)
              FilterChip(
                label: Text(dayNames[d - 1]),
                selected: _days.contains(d),
                onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(repeatSummary(_days),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Label', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sound,
            decoration: const InputDecoration(
                labelText: 'Sound', border: OutlineInputBorder()),
            items: [
              for (final k in AlarmConfig.alarmSounds.keys)
                DropdownMenuItem(
                    value: k, child: Text(k[0].toUpperCase() + k.substring(1))),
            ],
            onChanged: (v) => setState(() => _sound = v ?? _sound),
          ),
          const SizedBox(height: 16),
          Text('Pushups', style: tt.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Use default ($defaultN)'),
            value: _useDefault,
            onChanged: (v) => setState(() => _useDefault = v),
          ),
          if (!_useDefault)
            Row(children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _pushups > 1 ? () => setState(() => _pushups--) : null,
              ),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 100,
                  divisions: 99,
                  value: _pushups.toDouble(),
                  label: '$_pushups',
                  onChanged: (v) => setState(() => _pushups = v.round()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _pushups < 100 ? () => setState(() => _pushups++) : null,
              ),
              SizedBox(
                  width: 36,
                  child: Text('$_pushups', style: tt.titleMedium, textAlign: TextAlign.end)),
            ]),
          const SizedBox(height: 16),
          Text('Smart wake-up (watch)', style: tt.titleSmall),
          Row(children: [
            Expanded(
              child: Slider(
                min: 0,
                max: 60,
                divisions: 12,
                value: _smart.toDouble(),
                label: _smart == 0 ? 'Off' : '$_smart min',
                onChanged: (v) => setState(() => _smart = (v / 5).round() * 5),
              ),
            ),
            SizedBox(
                width: 56,
                child: Text(_smart == 0 ? 'Off' : '$_smart min',
                    style: tt.titleMedium, textAlign: TextAlign.end)),
          ]),
          Text(
              _smart == 0
                  ? 'Off'
                  : 'Ring up to $_smart min early when your watch detects light sleep',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (_smart > 0 && !_watchReachable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No watch connected \u2014 the alarm will ring at the set time',
                  style: tt.bodySmall?.copyWith(color: cs.error)),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
