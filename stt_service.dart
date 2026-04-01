import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/gemma_service.dart';
import '../models/assistant_mode.dart';
import '../models/analysis_result.dart';

class AssistantProvider extends ChangeNotifier {
  late final TTSService _tts;
  late final STTService _stt;
  late final GemmaService _gemma;
  late CameraController _cameraController;

  AssistantMode _mode = AssistantMode.scene;
  bool _isProcessing = false;
  bool _isListening = false;
  bool _isModelLoaded = false;
  bool _isCameraInitialized = false;
  String _statusMessage = "Initializing...";
  AnalysisResult? _lastResult;
  final List<AnalysisResult> _history = [];

  AssistantMode get mode => _mode;
  bool get isProcessing => _isProcessing;
  bool get isListening => _isListening;
  bool get isModelLoaded => _isModelLoaded;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isReady => _isModelLoaded && _isCameraInitialized;
  String get statusMessage => _statusMessage;
  AnalysisResult? get lastResult => _lastResult;
  List<AnalysisResult> get history => _history;
  CameraController get cameraController => _cameraController;

  AssistantProvider({required List<CameraDescription> cameras}) {
    _initialize(cameras);
  }

  Future<void> _initialize(List<CameraDescription> cameras) async {
    _tts = TTSService();
    _stt = STTService();
    _gemma = GemmaService();

    await _tts.initialize();
    await _stt.initialize();

    if (cameras.isNotEmpty) {
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      try {
        await _cameraController.initialize();
        _isCameraInitialized = true;
        _statusMessage = "Camera ready";
      } catch (e) {
        _statusMessage = "Camera error: $e";
      }
    }

    _statusMessage = "Loading AI model...";
    notifyListeners();

    try {
      await _gemma.loadModel();
      _isModelLoaded = true;
      _statusMessage = "Ready! Tap to describe your surroundings.";
      await _tts.speak("Vision Assistant ready. Tap the screen to describe your surroundings.");
    } catch (e) {
      _statusMessage = "Model loading failed. Using demo mode.";
      _isModelLoaded = true;
    }

    notifyListeners();
  }

  void setMode(AssistantMode newMode) {
    if (_mode != newMode) {
      _mode = newMode;
      HapticFeedback.mediumImpact();
      _tts.speak("Mode: ${newMode.displayName}");
      notifyListeners();
    }
  }

  void cycleMode() {
    final modes = AssistantMode.values;
    final nextIndex = (modes.indexOf(_mode) + 1) % modes.length;
    setMode(modes[nextIndex]);
  }

  Future<void> startListening() async {
    if (_isListening || _isProcessing) return;

    _isListening = true;
    HapticFeedback.lightImpact();
    notifyListeners();

    await _stt.startListening((result) {
      if (result.isNotEmpty) _handleVoiceCommand(result);
      _isListening = false;
      notifyListeners();
    });
  }

  void stopListening() {
    _stt.stopListening();
    _isListening = false;
    notifyListeners();
  }

  void _handleVoiceCommand(String command) {
    final cmd = command.toLowerCase();

    if (cmd.contains("describe") || cmd.contains("what") || cmd.contains("see")) {
      setMode(AssistantMode.scene);
      captureAndAnalyze();
    } else if (cmd.contains("read") || cmd.contains("text")) {
      setMode(AssistantMode.text);
      captureAndAnalyze();
    } else if (cmd.contains("navigate") || cmd.contains("obstacle")) {
      setMode(AssistantMode.navigation);
      captureAndAnalyze();
    } else if (cmd.contains("object") || cmd.contains("find")) {
      setMode(AssistantMode.objects);
      captureAndAnalyze();
    } else if (cmd.contains("help")) {
      _tts.speak("Say describe, read, navigate, or find.");
    } else if (cmd.contains("repeat")) {
      repeatLastResult();
    } else {
      captureAndAnalyze(customPrompt: command);
    }
  }

  Future<void> captureAndAnalyze({String? customPrompt}) async {
    if (_isProcessing || !_isCameraInitialized) return;

    _isProcessing = true;
    _statusMessage = "Capturing image...";
    HapticFeedback.mediumImpact();
    notifyListeners();

    try {
      final XFile imageFile = await _cameraController.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      _statusMessage = "Analyzing...";
      notifyListeners();

      final prompt = customPrompt ?? _mode.prompt;
      final description = await _gemma.analyzeImage(imageBytes, prompt);

      _lastResult = AnalysisResult(
        description: description,
        mode: _mode,
        timestamp: DateTime.now(),
        imagePath: imageFile.path,
      );

      _history.insert(0, _lastResult!);
      if (_history.length > 20) _history.removeLast();

      _statusMessage = description;
      await _tts.speak(description);
    } catch (e) {
      _statusMessage = "Error: Could not analyze image.";
      await _tts.speak("Sorry, I could not analyze the image.");
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void repeatLastResult() {
    if (_lastResult != null) {
      _tts.speak(_lastResult!.description);
    } else {
      _tts.speak("No previous description available.");
    }
  }

  void stopSpeaking() => _tts.stop();

  @override
  void dispose() {
    _cameraController.dispose();
    _tts.dispose();
    _stt.dispose();
    _gemma.dispose();
    super.dispose();
  }
}
