import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((message) => _isSpeaking = false);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stop();
    _isSpeaking = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  Future<void> setRate(double rate) async => await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  Future<void> setVolume(double volume) async => await _tts.setVolume(volume.clamp(0.0, 1.0));

  void dispose() => _tts.stop();
}
