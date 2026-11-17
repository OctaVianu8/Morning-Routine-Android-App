import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../services/alarm_sound_store.dart';
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

  static const _customKey = '__custom__';
  late final int _alarmId;
  String? _customPath;
  String? _customName;

  /// Files imported during this editing session (orphans unless saved).
  final List<String> _imported = [];
  bool _saved = false;
  bool _picking = false;
  AudioPlayer? _player;
  bool _previewing = false;

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
    _alarmId = e?.id ?? app.newAlarmId();
    _sound = e?.sound ?? 'classic';
    _customPath = e?.customSoundPath;
    _customName = e?.customSoundName;
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
    _stopPreview(dispose: true);
    if (!_saved) {
      // Cancelled: discard files imported in this session, keep the saved one.
      for (final f in _imported) {
        AlarmSoundStore.instance.delete(f);
      }
    }
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _stopPreview({bool dispose = false}) async {
    final p = _player;
    if (dispose) _player = null;
    if (!dispose && mounted && _previewing) setState(() => _previewing = false);
    _previewing = false;
    if (p == null) return;
    try {
      await p.stop();
      if (dispose) await p.dispose();
    } catch (e) {
      debugPrint('preview stop failed: $e');
    }
  }

  Future<void> _togglePreview() async {
    if (_previewing) return _stopPreview();
    try {
      final p = _player ??= AudioPlayer();
      p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _previewing = false);
      });
      await p.setVolume(0.5);
      final custom = _sound == _customKey && _customPath != null;
      if (custom && !await AlarmSoundStore.instance.exists(_customPath!)) {
        _toast('That sound file is missing; the default sound will be used.');
        return;
      }
      await p.play(custom
          ? DeviceFileSource(_customPath!)
          : AssetSource((AlarmConfig.alarmSounds[_sound] ?? AlarmConfig.alarmSounds['classic']!)
              .replaceFirst('assets/', '')));
      if (mounted) setState(() => _previewing = true);
    } catch (e) {
      debugPrint('preview failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Opens the picker; returns true if a new file was imported.
  Future<bool> _chooseFile() async {
    if (_picking) return false;
    _picking = true;
    try {
      await _stopPreview();
      final store = AlarmSoundStore.instance;
      final r = await store.pickAndImport(_alarmId);
      if (!mounted) {
        if (r != null) await store.delete(r.path);
        return false;
      }
      if (r == null) {
        if (store.lastError != null) _toast(store.lastError!);
        return false;
      }
      final old = _customPath;
      setState(() {
        _imported.add(r.path);
        _customPath = r.path;
        _customName = r.name;
        _sound = _customKey;
      });
      // A replaced file from this session was never saved: drop it now.
      if (old != null && _imported.contains(old)) {
        _imported.remove(old);
        await store.delete(old);
      }
      return true;
    } finally {
      _picking = false;
    }
  }

  void _removeCustom() {
    _stopPreview();
    final old = _customPath;
    setState(() {
      if (old != null && _imported.contains(old)) {
        _imported.remove(old);
        AlarmSoundStore.instance.delete(old);
      }
      _customPath = null;
      _customName = null;
      _sound = 'classic';
    });
  }

  void _save() {
    _stopPreview();
    final app = context.read<AppState>();
    final e = widget.existing;
    final useCustom = _sound == _customKey && _customPath != null;
    final alarm = AlarmConfig(
      id: _alarmId,
      hour: _time.hour,
      minute: _time.minute,
      weekdays: _days,
      enabled: true,
      label: _label.text.trim(),
      pushupsOverride: _useDefault ? null : _pushups,
      sound: useCustom ? 'classic' : _sound,
      smartWakeMinutes: _smart,
      customSoundPath: useCustom ? _customPath : null,
      customSoundName: useCustom ? _customName : null,
    );
    app.upsertAlarm(alarm);
    _saved = true;
    // Only now remove files the saved alarm no longer uses.
    final store = AlarmSoundStore.instance;
    final keep = alarm.customSoundPath;
    for (final f in [?e?.customSoundPath, ..._imported]) {
      if (f != keep) store.delete(f);
    }
    store.pruneUnused([for (final a in app.alarms) ?a.customSoundPath]);
    final rel = relativeTime(alarm.nextOccurrence(DateTime.now()).difference(DateTime.now()));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Alarm set for $rel from now')));
    Navigator.of(context).pop();
  }

  void _delete() {
    _stopPreview();
    context.read<AppState>().deleteAlarm(widget.existing!.id);
    final old = widget.existing!.customSoundPath;
    if (old != null) AlarmSoundStore.instance.delete(old);
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('$_sound$_customPath'),
                initialValue: _sound,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Sound', border: OutlineInputBorder()),
                items: [
                  for (final k in AlarmConfig.alarmSounds.keys)
                    DropdownMenuItem(
                        value: k, child: Text(k[0].toUpperCase() + k.substring(1))),
                  const DropdownMenuItem(
                      value: _customKey, child: Text('From my phone\u2026')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  _stopPreview();
                  if (v == _customKey && _customPath == null) {
                    await _chooseFile();
                  } else {
                    setState(() => _sound = v);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _previewing ? 'Stop preview' : 'Play preview',
              icon: Icon(_previewing ? Icons.stop : Icons.play_arrow),
              onPressed: _togglePreview,
            ),
          ]),
          if (_sound == _customKey && _customPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.music_note, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_customName ?? 'Custom sound',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
                  ),
                ]),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: _chooseFile, child: const Text('Change')),
                  TextButton(
                      onPressed: _removeCustom,
                      child: const Text('Remove (use default)')),
                ]),
              ]),
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
