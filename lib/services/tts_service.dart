import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin, never-throwing wrapper around flutter_tts.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool enabled = true;
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      if (!kIsWeb && Platform.isIOS) {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }
      _inited = true;
    } catch (e) {
      debugPrint('TtsService.init failed: $e');
    }
  }

  Future<void> speak(String text, {bool interrupt = true}) async {
    if (!enabled || text.trim().isEmpty) return;
    try {
      if (!_inited) await init();
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TtsService.speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TtsService.stop failed: $e');
    }
  }
}
