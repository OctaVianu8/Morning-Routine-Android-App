import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/ring_screen.dart';
import 'services/alarm_scheduler.dart';
import 'services/app_state.dart';
import 'services/reminder_service.dart';
import 'services/sound_service.dart';
import 'services/tts_service.dart';
import 'services/wear_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));

  final state = await AppState.load();

  // Each service swallows its own errors; a broken TTS engine or notification
  // channel must never keep the alarm from working.
  await AlarmScheduler.instance.init();
  await Future.wait([
    TtsService.instance.init(),
    SoundService.instance.init(),
    ReminderService.instance.init(),
  ]);
  TtsService.instance.enabled = state.settings.voiceEnabled;

  var askedPermissions = false;
  Future<void> syncAlarms() async {
    TtsService.instance.enabled = state.settings.voiceEnabled;
    if (!askedPermissions && state.alarms.any((a) => a.enabled)) {
      askedPermissions = true;
      await AlarmScheduler.instance.requestPermissions();
    }
    await AlarmScheduler.instance.sync(state.alarms, state.settings);
    await WearService.instance.syncPlan(state.alarms);
  }

  state.onAlarmsChanged = syncAlarms;
  state.onHabitsChanged = () => ReminderService.instance.syncHabits(state.habits);

  runApp(ChangeNotifierProvider.value(value: state, child: const MorningGloryApp()));

  unawaited(syncAlarms());
  unawaited(ReminderService.instance.syncHabits(state.habits));
}

class MorningGloryApp extends StatefulWidget {
  const MorningGloryApp({super.key});

  @override
  State<MorningGloryApp> createState() => _MorningGloryAppState();
}

class _MorningGloryAppState extends State<MorningGloryApp> with WidgetsBindingObserver {
  StreamSubscription<Set<int>>? _ringSub;

  /// Alarm whose RingScreen is currently on the navigator, if any.
  int? _showing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ringSub = AlarmScheduler.instance.ringingIds.listen(_onRinging);
    // The app may have been launched *by* a ringing alarm (full-screen intent).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRinging());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ringSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkRinging();
    // Repeating alarms are re-armed from Dart, so top up whenever we come back.
    final app = context.read<AppState>();
    unawaited(AlarmScheduler.instance.sync(app.alarms, app.settings));
    unawaited(WearService.instance.syncPlan(app.alarms));
  }

  Future<void> _checkRinging() async =>
      _onRinging(await AlarmScheduler.instance.queryRinging());

  void _onRinging(Set<int> ids) {
    if (ids.isEmpty || _showing != null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final id = ids.first;
    _showing = id;
    nav
        .push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => RingScreen(alarmId: id),
        ))
        .whenComplete(() {
      _showing = null;
      // Another alarm may have started while this one was on screen.
      _checkRinging();
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFFF8A3D); // sunrise orange
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
        );
    return MaterialApp(
      title: 'MorningGlory',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}
