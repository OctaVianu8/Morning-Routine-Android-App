import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Short UI sounds (rep chime, success). Players never take audio focus and
/// mix with other audio, so the ringing alarm keeps playing.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const _poolSize = 3;
  final List<AudioPlayer> _chimes = [];
  AudioPlayer? _success;
  int _next = 0;
  bool _inited = false;

  static final AudioContext _ctx = AudioContext(
    android: const AudioContextAndroid(
      audioFocus: AndroidAudioFocus.none,
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  Future<AudioPlayer> _make(String asset) async {
    final p = AudioPlayer();
    await p.setAudioContext(_ctx);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setSource(AssetSource(asset));
    return p;
  }

  Future<void> init() async {
    if (_inited) return;
    try {
      for (var i = 0; i < _poolSize; i++) {
        _chimes.add(await _make('sounds/chime.wav'));
      }
      _success = await _make('sounds/success.wav');
      _inited = true;
    } catch (e) {
      debugPrint('SoundService.init failed: $e');
    }
  }

  Future<void> chime() async {
    try {
      if (!_inited) await init();
      if (_chimes.isEmpty) return;
      final p = _chimes[_next++ % _chimes.length];
      await p.stop();
      await p.resume();
    } catch (e) {
      debugPrint('SoundService.chime failed: $e');
    }
  }

  Future<void> success() async {
    try {
      if (!_inited) await init();
      final p = _success;
      if (p == null) return;
      await p.stop();
      await p.resume();
    } catch (e) {
      debugPrint('SoundService.success failed: $e');
    }
  }
}
