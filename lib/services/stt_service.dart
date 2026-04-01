import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class STTService {
  final SpeechToText _stt = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  Future<void> initialize() async {
    _isInitialized = await _stt.initialize(
      onError: (error) => _isListening = false,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') _isListening = false;
      },
    );
  }

  Future<void> startListening(Function(String) onResult) async {
    if (!_isInitialized) await initialize();
    if (_isListening) return;

    _isListening = true;

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: false,
      cancelOnError: true,
    );
  }

  void stopListening() {
    _stt.stop();
    _isListening = false;
  }

  void dispose() {
    _stt.stop();
    _stt.cancel();
  }
}
