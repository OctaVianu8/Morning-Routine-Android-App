# MorningGlory for Wear OS (smart wake-up companion)

A small watch app for Samsung Galaxy Watch 4/5/6 (Wear OS 3 to 5, also newer).
The phone app tells the watch about an alarm at time T with a window of W
minutes. The watch watches your movement (and heart rate, if allowed) starting
60 minutes before T. If it sees you in light sleep or stirring during
[T - W, T), it tells the phone to ring now instead of at T.

The watch app uses the same package name and the same signing key as the phone
app. That is required: the Wear data layer only links apps with the same
package and signature.

## Build

```bash
cd wear
```

```bash
export ANDROID_HOME=/opt/sdk/android
```

```bash
./gradlew :app:testDebugUnitTest :app:assembleRelease
```

The APK is `app/build/outputs/apk/release/app-release.apk`. Copy it to
`MorningGlory-wear.apk` for the commands below.

## Install on the watch (first time, step by step)

You need the APK file, a computer, and a Wi-Fi network that both the computer
and the watch are connected to.

### 1. Install adb (platform-tools) on the computer

Download "SDK Platform-Tools" from the Android developer site and unzip it.

Windows: unzip, open the folder in Explorer, type `cmd` in the address bar.
Then check it works:

```bash
adb version
```

macOS (Homebrew):

```bash
brew install android-platform-tools
```

Linux (Debian/Ubuntu):

```bash
sudo apt install adb
```

### 2. Enable developer options on the watch

1. On the watch open Settings, then About watch, then Software information.
2. Tap "Software version" 7 times quickly. Developer options appear.
3. Go back to Settings, then Developer options.
4. Turn on "ADB debugging".
5. Turn on "Debug over Wi-Fi" / "Wireless debugging".
6. The watch must be on the same Wi-Fi as the computer.

### 3. Find the IP address and ports

In Developer options, "Wireless debugging" shows the IP address and port
(for example `192.168.1.50:37215`). Tap "Pair new device" to see a pairing code
and a separate pairing IP:port.

### 4. Pair and connect

Pair once (use the pairing port and enter the 6 digit code when asked):

```bash
adb pair 192.168.1.50:40123
```

Then connect (use the normal Wireless debugging port, not the pairing port):

```bash
adb connect 192.168.1.50:37215
```

Check that the watch is listed:

```bash
adb devices
```

### 5. Install the app

```bash
adb -s 192.168.1.50:37215 install -r MorningGlory-wear.apk
```

If the phone app is not installed on the paired phone yet, install it first.

### 6. First start

1. Open MorningGlory on the watch once.
2. Tap "Grant sensor access" and allow body sensors (heart rate) and
   notifications. Without heart rate it still works using movement only.
3. If you have the Galaxy Watch battery saver on, exclude MorningGlory from
   battery optimisation if the watch kills it overnight.

### 7. Turn Wireless debugging off again

It drains the battery. On the watch: Developer options, turn off "ADB
debugging" and "Wireless debugging". You can disconnect on the computer:

```bash
adb disconnect
```

## Verify from the phone

Open the phone app, Settings, Smart watch, and press Test. The watch should
vibrate twice briefly and the phone shows that the watch answered. Then set an
alarm with a smart wake window; the watch app should show "Smart wake: HH:MM,
window N min".

## How it decides

This is a movement based estimate, not medical sleep staging. In deep sleep
and REM your body is mostly still; light sleep and short arousals show more
movement. Starting 60 minutes before the alarm the watch records the
accelerometer (about 10 Hz) and, if permitted, heart rate, in 30 second
epochs. It learns your own still level from the earlier epochs, and inside the
window it triggers when:

- at least 2 of the last 4 epochs show movement, or
- one epoch shows movement and heart rate is at least 8 % above your baseline.

It never triggers in the last minute before the alarm and never twice. If the
watch looks like it is lying on a table (no heart rate and perfectly flat
motion) it does nothing. If it does not trigger, the alarm rings at the normal
time.

## Battery

Untested estimate: accelerometer batching plus an occasional heart rate sample
for one hour before the alarm should cost a few percent of battery per night.
Real numbers depend on the watch model and settings.

## Troubleshooting

- The watch must be worn and connected to the phone by Bluetooth. If it never
  signals, nothing breaks: the alarm rings at the normal time.
- The watch app says "no plan received yet": open the phone app, check Smart
  watch settings, and make sure both apps are signed with the same key (use
  the APKs built from this repo).
- No heart rate: grant sensor access in the watch app, or accept movement only.
- `adb connect` fails: the pairing port and connection port differ, and the
  connection port changes whenever Wireless debugging is toggled.
- Install fails with a signature error: uninstall the other build of
  `com.octavianu.morning_glory` from the watch first.
