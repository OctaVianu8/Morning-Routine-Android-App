import 'package:flutter_test/flutter_test.dart';
import 'package:morning_glory/models/alarm_config.dart';
import 'package:morning_glory/services/alarm_scheduler.dart';

AlarmConfig _a({String? path, String? name}) => AlarmConfig(
    id: 1, hour: 7, minute: 0, customSoundPath: path, customSoundName: name);

void main() {
  test('custom sound JSON round trip and legacy JSON', () {
    final a = _a(path: '/data/app_flutter/alarm_sounds/1_2.mp3', name: 'Song.mp3');
    final b = AlarmConfig.fromJson(a.toJson());
    expect(b.customSoundPath, a.customSoundPath);
    expect(b.customSoundName, 'Song.mp3');
    final legacy = Map<String, dynamic>.from(a.toJson())
      ..remove('customSoundPath')
      ..remove('customSoundName');
    final c = AlarmConfig.fromJson(legacy);
    expect(c.customSoundPath, isNull);
    expect(c.hasCustomSound, isFalse);
    expect(c.audioPath, c.assetPath);
  });

  test('audioPath selection', () {
    expect(_a().audioPath, 'assets/sounds/alarm_classic.wav');
    expect(_a(path: '/x/alarm_sounds/a.mp3').audioPath, '/x/alarm_sounds/a.mp3');
    expect(AlarmConfig.deviceAudioPath('/x/y/alarm_sounds/a.mp3', ios: false),
        '/x/y/alarm_sounds/a.mp3');
    expect(
        AlarmConfig.deviceAudioPath(
            '/var/mobile/Containers/Data/Application/U/Documents/alarm_sounds/a.mp3',
            ios: true),
        'alarm_sounds/a.mp3');
  });

  test('scheduler falls back to built-in when file is missing', () {
    final c = _a(path: '/x/a.mp3');
    expect(resolveAlarmAudioPath(c, customExists: true), '/x/a.mp3');
    expect(resolveAlarmAudioPath(c, customExists: false), c.assetPath);
    expect(resolveAlarmAudioPath(_a(), customExists: false), _a().assetPath);
  });

  test('copyWith clears custom sound', () {
    final c = _a(path: '/x/a.mp3', name: 'a.mp3');
    expect(c.copyWith(label: 'hi').customSoundPath, '/x/a.mp3');
    final d = c.copyWith(clearCustomSound: true);
    expect(d.customSoundPath, isNull);
    expect(d.customSoundName, isNull);
  });
}
