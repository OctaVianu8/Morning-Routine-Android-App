import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/alarm_scheduler.dart';
import '../services/app_state.dart';
import '../services/reminder_service.dart';
import '../services/tts_service.dart';
import 'ring_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final st = state.settings;
    void update(AppSettings s) => state.updateSettings(s);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _Header('Alarm'),
        _SliderTile(
          title: 'Pushups to stop the alarm',
          value: st.pushupTarget.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          label: (v) => '${v.round()}',
          onChanged: (v) => update(st.copyWith(pushupTarget: v.round())),
        ),
        _SliderTile(
          title: 'Alarm volume',
          value: st.alarmVolume.clamp(0.1, 1.0),
          min: 0.1,
          max: 1.0,
          divisions: 9,
          label: (v) => '${(v * 100).round()}%',
          onChanged: (v) => update(st.copyWith(alarmVolume: v)),
        ),
        SwitchListTile(
          title: const Text('Vibrate'),
          value: st.vibrate,
          onChanged: (v) => update(st.copyWith(vibrate: v)),
        ),
        const _Header('Escape hatch'),
        SwitchListTile(
          title: const Text('Enable escape hatch'),
          subtitle: const Text(
              "Solve math problems to stop the alarm if the camera can't see you."),
          value: st.fallbackEnabled,
          onChanged: (v) => update(st.copyWith(fallbackEnabled: v)),
        ),
        _SliderTile(
          title: 'Unlocks after',
          value: st.fallbackDelaySec.clamp(30, 300).toDouble(),
          min: 30,
          max: 300,
          divisions: 27,
          enabled: st.fallbackEnabled,
          label: (v) => '${v.round()} s',
          onChanged: (v) => update(st.copyWith(fallbackDelaySec: v.round())),
        ),
        _SliderTile(
          title: 'Math problems',
          value: st.mathProblems.clamp(1, 10).toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          enabled: st.fallbackEnabled,
          label: (v) => '${v.round()}',
          onChanged: (v) => update(st.copyWith(mathProblems: v.round())),
        ),
        const _Header('Voice'),
        SwitchListTile(
          title: const Text('Voice enabled'),
          value: st.voiceEnabled,
          onChanged: (v) => update(st.copyWith(voiceEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Count reps aloud'),
          value: st.countAloud,
          onChanged: st.voiceEnabled
              ? (v) => update(st.copyWith(countAloud: v))
              : null,
        ),
        SwitchListTile(
          title: const Text('Read remaining habits after alarm'),
          value: st.speakHabitsAfterAlarm,
          onChanged: st.voiceEnabled
              ? (v) => update(st.copyWith(speakHabitsAfterAlarm: v))
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Test voice'),
          onTap: () => TtsService.instance
              .speak('Good morning! Time to do ${st.pushupTarget} pushups.'),
        ),
        const _Header('Permissions'),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Check alarm permissions'),
          subtitle: const Text('Notifications, exact alarms and full-screen alerts'),
          onTap: () async {
            await AlarmScheduler.instance.requestPermissions();
            await ReminderService.instance.requestPermissions();
          },
        ),
        ListTile(
          leading: const Icon(Icons.battery_alert_outlined),
          title: const Text('Battery optimisation'),
          subtitle: const Text(
              'On some phones (Xiaomi, Huawei, Samsung, OnePlus...) disable battery '
              'optimisation for this app so alarms ring reliably.'),
          isThreeLine: true,
          trailing: TextButton(
            onPressed: openAppSettings,
            child: const Text('Open'),
          ),
        ),
        const _Header('Practice'),
        ListTile(
          leading: const Icon(Icons.fitness_center),
          title: const Text('Practice pushups'),
          subtitle: const Text('Try the camera counter without an alarm'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const RingScreen(alarmId: -1, practice: true))),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600)),
      );
}

/// Slider that keeps a local value while dragging and commits on release.
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final double value, min, max;
  final int divisions;
  final bool enabled;
  final String Function(double) label;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = _drag ?? widget.value;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fg = widget.enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.title, style: tt.bodyLarge?.copyWith(color: fg))),
              Text(widget.label(v),
                  style: tt.titleSmall?.copyWith(color: widget.enabled ? cs.primary : fg)),
            ],
          ),
          Slider(
            value: v.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.enabled ? (x) => setState(() => _drag = x) : null,
            onChangeEnd: (x) {
              widget.onChanged(x);
              setState(() => _drag = null);
            },
          ),
        ],
      ),
    );
  }
}
