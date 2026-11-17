import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/alarm_config.dart';
import '../models/habit.dart';
import '../pushup/pose_camera_view.dart';
import '../pushup/pushup_counter.dart';
import '../services/alarm_scheduler.dart';
import '../services/app_state.dart';
import '../services/briefing_service.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';
import 'math_challenge_screen.dart';

/// Full-screen screen shown while an alarm rings. Stops the alarm only after
/// the pushup target is reached (or the math escape hatch is solved).
class RingScreen extends StatefulWidget {
  const RingScreen({super.key, required this.alarmId, this.practice = false});
  final int alarmId;
  final bool practice;

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> {
  late final AppState _app;
  late final int _target;
  late final DateTime _opened;
  AlarmConfig? _alarm;
  Timer? _clock;
  DateTime _now = DateTime.now();
  int _count = 0;
  PushupPhase _phase = PushupPhase.noBody;
  bool _finished = false;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _opened = DateTime.now();
    _alarm = _app.alarmById(widget.alarmId);
    _target = widget.practice
        ? _app.settings.pushupTarget
        : _app.pushupTargetFor(widget.alarmId);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // The phone is usually propped up on the floor, often sideways. Letting the
    // UI rotate keeps the camera image upright, which the posture check needs.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    if (!widget.practice) {
      BriefingService.instance.prefetch(_app);
      final t = DateFormat.jm().format(_opened);
      TtsService.instance
          .speak("Good morning! It's $t. Do $_target pushups to stop the alarm.");
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _onRep(int count) {
    if (_finished || !mounted) return;
    setState(() => _count = count);
    SoundService.instance.chime();
    if (_app.settings.countAloud && count < _target) {
      TtsService.instance.speak('$count');
    }
    if (count >= _target) _finish(pushupsDone: true);
  }

  Future<void> _finish({required bool pushupsDone}) async {
    if (_finished) return;
    _finished = true;
    if (mounted) setState(() => _success = true);
    final settings = _app.settings;
    SoundService.instance.success();
    if (!widget.practice) {
      await AlarmScheduler.instance.stop(widget.alarmId);
      if (pushupsDone) _app.setDone(Habit.pushupsId, true);
      final alarm = _app.alarmById(widget.alarmId) ?? _alarm;
      if (alarm != null) {
        _app.upsertAlarm(alarm.repeats ? alarm : alarm.copyWith(enabled: false));
      }
      if (settings.briefingEnabled) {
        unawaited(BriefingService.instance.speak(_app, afterAlarm: true));
      } else if (settings.speakHabitsAfterAlarm) {
        final remaining = _app.enabledHabits
            .where((h) => !_app.isDone(h.id))
            .map((h) => h.title)
            .toList();
        final msg = StringBuffer('Great job! Alarm off.');
        if (remaining.isNotEmpty) {
          msg.write(' Next up: ${remaining.join(', ')}.');
        }
        TtsService.instance.speak(msg.toString());
      }
    } else {
      TtsService.instance.speak('Great job!');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openMath() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MathChallengeScreen(problems: _app.settings.mathProblems),
    ));
    if (ok == true && mounted) _finish(pushupsDone: false);
  }

  String get _hint => switch (_phase) {
        PushupPhase.noBody => 'Place the phone on the floor and get into frame',
        PushupPhase.notInPosition => 'Get into pushup position',
        PushupPhase.up => 'Go down',
        PushupPhase.down => 'Push up!',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = _app.settings;
    const onDark = Colors.white;
    final remainingSec = settings.fallbackDelaySec - _now.difference(_opened).inSeconds;
    final label = _alarm?.label ?? '';
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 520; // landscape phone
    final ring = compact ? size.height * 0.34 : 200.0;

    final overlay = _success
        ? Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 120, color: cs.primary),
              const SizedBox(height: 16),
              Text(widget.practice ? 'Practice complete!' : 'Alarm off. Great job!',
                  style: tt.headlineMedium?.copyWith(color: onDark)),
            ]),
          )
        : SafeArea(
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 20),
              child: Column(
                children: [
                  if (widget.practice)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  Text(DateFormat.jm().format(_now),
                      style: (compact ? tt.headlineSmall : tt.displayMedium)
                          ?.copyWith(color: onDark, fontWeight: FontWeight.w300)),
                  if (label.isNotEmpty)
                    Text(label, style: tt.titleMedium?.copyWith(color: onDark)),
                  const Spacer(),
                  SizedBox(
                    width: ring,
                    height: ring,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: (_count / _target).clamp(0.0, 1.0),
                          strokeWidth: compact ? 8 : 12,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Text('$_count / $_target',
                          style: (compact ? tt.headlineSmall : tt.displaySmall)
                              ?.copyWith(color: onDark, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  SizedBox(height: compact ? 6 : 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 4 : 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(_hint,
                        textAlign: TextAlign.center,
                        style: (compact ? tt.titleMedium : tt.titleLarge)
                            ?.copyWith(color: onDark)),
                  ),
                  const Spacer(),
                  if (!widget.practice && settings.fallbackEnabled)
                    TextButton(
                      onPressed: remainingSec > 0 ? null : _openMath,
                      child: Text(
                        remainingSec > 0
                            ? "Can't do pushups? (available in ${remainingSec}s)"
                            : "Can't do pushups?",
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                ],
              ),
            ),
          );

    return PopScope(
      canPop: widget.practice,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          PushupCameraView(
            onRep: _onRep,
            onPhase: (p) {
              if (mounted) setState(() => _phase = p);
            },
          ),
          overlay,
        ]),
      ),
    );
  }
}
