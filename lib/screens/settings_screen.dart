import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/alarm_scheduler.dart';
import '../services/app_state.dart';
import '../services/briefing_service.dart';
import '../services/calendar_service.dart';
import '../services/weather_service.dart';
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
          subtitle: st.briefingEnabled
              ? const Text('The morning briefing replaces this while it is on.')
              : null,
          value: st.speakHabitsAfterAlarm,
          onChanged: st.voiceEnabled && !st.briefingEnabled
              ? (v) => update(st.copyWith(speakHabitsAfterAlarm: v))
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Test voice'),
          onTap: () => TtsService.instance
              .speak('Good morning! Time to do ${st.pushupTarget} pushups.'),
        ),
        const _Header('Morning briefing'),
        const _BriefingSettings(),
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

class _BriefingSettings extends StatefulWidget {
  const _BriefingSettings();

  @override
  State<_BriefingSettings> createState() => _BriefingSettingsState();
}

class _BriefingSettingsState extends State<_BriefingSettings> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  final _nameFocus = FocusNode();
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>().settings;
    _name = TextEditingController(text: st.userName);
    _city = TextEditingController(text: st.city);
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _saveName();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _saveName() {
    final app = context.read<AppState>();
    final v = _name.text.trim();
    if (v != app.settings.userName) app.updateSettings(app.settings.copyWith(userName: v));
  }

  Future<void> _lookUp() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final text = _city.text.trim();
    if (text.isEmpty) {
      app.updateSettings(app.settings.copyWith(clearCity: true));
      return;
    }
    setState(() => _looking = true);
    final r = await WeatherService.instance.geocode(text);
    if (!mounted) return;
    setState(() => _looking = false);
    if (r == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text("City not found (or you're offline)")));
      return;
    }
    app.updateSettings(app.settings
        .copyWith(city: text, cityLat: r.lat, cityLon: r.lon, cityLabel: r.label));
  }

  Future<void> _setCalendar(bool on) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    if (on && !await CalendarService.instance.requestPermission()) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Calendar permission was not granted')));
      return;
    }
    app.updateSettings(app.settings.copyWith(briefingCalendar: on));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.settings;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Speak a briefing after the alarm'),
          subtitle: const Text('Date, weather, calendar, habits and streak.'),
          value: st.briefingEnabled,
          onChanged: (v) => app.updateSettings(st.copyWith(briefingEnabled: v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _name,
            focusNode: _nameFocus,
            enabled: st.briefingEnabled,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
            onSubmitted: (_) => _saveName(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _city,
            enabled: st.briefingEnabled,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'City for weather',
              helperText: st.cityLabel.isEmpty ? null : st.cityLabel,
              suffixIcon: _looking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : TextButton(onPressed: _lookUp, child: const Text('Look up')),
            ),
            onSubmitted: (_) => _lookUp(),
          ),
        ),
        SwitchListTile(
          title: const Text('Include weather'),
          subtitle: const Text('Sends only your city name and its coordinates to Open-Meteo.'),
          value: st.briefingWeather,
          onChanged: st.briefingEnabled
              ? (v) => app.updateSettings(st.copyWith(briefingWeather: v))
              : null,
        ),
        SwitchListTile(
          title: const Text('Include calendar events'),
          subtitle: const Text('Read on the phone only; never uploaded.'),
          value: st.briefingCalendar,
          onChanged: st.briefingEnabled ? _setCalendar : null,
        ),
        ListTile(
          leading: const Icon(Icons.play_circle_outline),
          title: const Text('Play briefing now'),
          onTap: () => unawaited(BriefingService.instance.speak(app)),
        ),
      ],
    );
  }
}
