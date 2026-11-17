# MorningGlory

A morning-routine app whose alarm **does not stop until you do your pushups**.
The phone camera tracks your body with on-device pose estimation, every rep
plays a chime, and the alarm goes quiet only when you hit your target
(20 by default, configurable globally and per alarm).

Built with Flutter: Android today, iOS from the same codebase.

## Features

- **Pushup alarm** – full-screen alarm over the lock screen, volume enforced,
  no stop/snooze button, back button disabled, keeps ringing if the
  notification is swiped away. Each alarm can use a built-in sound or an audio file you pick from your phone.
- **Camera rep counter** – Google ML Kit pose detection, fully on-device (no
  network, no video leaves the phone). A rep is elbow angle going below ~95°
  and back above ~150°, and only counts while the body is in a plank-like
  position, so bending your arms while standing doesn't work.
- **Chime per rep**, spoken rep count and a spoken good-morning announcement
  (text-to-speech).
- **Escape hatch** – if the camera can't see you (dark room, injury), a
  deliberately annoying math challenge unlocks after 60 s of ringing. Delay
  and problem count are configurable; it can be switched off for strict mode.
- **Habits** – recommended checklist (pushups, water, make the bed, yogurt,
  5 minutes outside, …), custom habits, daily reminder notifications.
  Finishing the alarm ticks off "Do pushups" automatically.
- **Day streak** – a day counts when every enabled habit is ticked. The Today
  tab shows an animated flame, the last seven days, your best streak and the
  next milestone (3, 7, 14, 30, …); completing the routine triggers a confetti
  celebration with sound, haptics and voice.
- **Morning briefing** – after the alarm stops (or on demand from the Today
  tab) the phone speaks a natural briefing composed from real data, no LLM:
  greeting with your name, date, weather, today's calendar events, remaining
  habits, streak and next alarm. Weather comes from Open-Meteo (no API key) and
  only the city name you type (geocoding) and its coordinates (forecast) leave
  the device; no device location is used. Calendar events are read on the
  device and never uploaded.
- **Smart wake-up (Wear OS)** – give an alarm a wake window of up to 60
  minutes; a companion watch app (from `wear/`, installed per
  `wear/README.md`) watches your movement from an hour before the alarm and,
  if it sees light sleep inside the window, rings the alarm early. It never
  rings earlier than the window and falls back to the normal time if the watch
  says nothing. A **dry-run mode (on by default)** only records when the
  watch would have woken you while the alarm rings normally; review the
  recorded nights under Settings > Smart watch > Recent nights, then switch it
  off to let the watch wake you early. Needs a Galaxy Watch 4 or newer (Wear OS 3+); it is a
  movement-based estimate, not medical sleep staging. Android only.
- **Practice mode** – try the pushup counter without an alarm.

## Project layout

```
lib/
  main.dart                  app bootstrap, routes a ringing alarm to RingScreen
  models/                    AlarmConfig, Habit, AppSettings (plain JSON)
  services/
    app_state.dart           persisted state (shared_preferences) + ChangeNotifier
    alarm_scheduler.dart     wraps the `alarm` plugin; keeps the OS schedule in sync
    reminder_service.dart    daily habit notifications
    tts_service.dart         text-to-speech
    briefing_service.dart    composes + speaks the morning briefing (pure composer, unit tested)
    weather_service.dart     Open-Meteo geocoding + forecast (cached, offline-safe)
    calendar_service.dart    today's events from the device calendar (read-only)
    sound_service.dart       chime / success sounds
    wear_service.dart        Wear OS link (plan, ping, status) + pure plan/pull-forward logic
  pushup/
    pushup_counter.dart      pure-Dart rep state machine (unit tested)
    pose_camera_view.dart    camera stream -> ML Kit -> PushupCounter + skeleton overlay
  screens/                   Today, Alarms, Settings, alarm editor, ring screen, math challenge
android/app/src/main/kotlin/  WearBridge (MethodChannel morning_glory/wear), WearListenerService (early wake)
wear/                        Wear OS companion app (separate Gradle project, see wear/README.md)
assets/sounds/               synthesized alarm / chime sounds
test/                        unit tests (counter logic, models, state)
```

## Build (Android)

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Requires
Flutter 3.50+, Android SDK platform 37, JDK 17+. The release build is signed
with the debug key; add your own signing config before publishing.

Both the phone APK and the watch APK in `wear/` are signed with
`android/keystore/dev.keystore` and must share it: the Wear OS data layer only
connects apps with the same package name **and** signature.

### First run on the phone

1. Create an alarm – the app asks for notification, exact-alarm and camera
   permissions.
2. On Xiaomi / Huawei / Samsung / OnePlus, disable battery optimisation for
   MorningGlory (Settings → Permissions in the app has a shortcut). Aggressive
   OEM task killers are the main reason alarms get dropped on Android.
3. Use **Practice pushups** once to find a phone position that sees your whole
   upper body: on the floor, leaning against something, 1–1.5 m away, side-on
   works best.

## Porting to iPhone

All app code is shared; the iOS project in `ios/` is already configured
(camera usage string, background audio, background task id, alarm plugin
registration in `AppDelegate.swift`). On a Mac:

```bash
flutter pub get
```

```bash
cd ios && pod install --repo-update
```

```bash
flutter run
```

Things to know on iOS:

- Set the deployment target to iOS 15.5+ in Xcode and in `ios/Podfile`
  (ML Kit requirement) and pick your signing team.
- iOS has no equivalent of Android's full-screen alarm intent. The alarm
  plugin keeps the sound going via background audio, but the user has to tap
  the notification to open the pushup screen, and force-quitting the app
  stops the alarm. That is a platform limit, not something app code can fix.
