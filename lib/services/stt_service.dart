import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  final SpeechToText _stt = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _stt.initialize();
    return _isInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    Function()? onDone,
  }) async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }

    _isListening = true;
    
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          _isListening = false;
          onDone?.call();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _stt.stop();
  }

  void dispose() {
    _stt.stop();
  }
}
