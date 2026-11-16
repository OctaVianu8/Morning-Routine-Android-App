# MorningGlory

A morning-routine app whose alarm **does not stop until you do your pushups**.
The phone camera tracks your body with on-device pose estimation, every rep
plays a chime, and the alarm goes quiet only when you hit your target
(20 by default, configurable globally and per alarm).

Built with Flutter: Android today, iOS from the same codebase.

## Features

- **Pushup alarm** – full-screen alarm over the lock screen, volume enforced,
  no stop/snooze button, back button disabled, keeps ringing if the
  notification is swiped away.
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
  5 minutes outside, …), custom habits, daily reminder notifications, streak.
  Finishing the alarm ticks off "Do pushups" automatically.
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
    sound_service.dart       chime / success sounds
  pushup/
    pushup_counter.dart      pure-Dart rep state machine (unit tested)
    pose_camera_view.dart    camera stream -> ML Kit -> PushupCounter + skeleton overlay
  screens/                   Today, Alarms, Settings, alarm editor, ring screen, math challenge
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
