import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import '../models/assistant_mode.dart';
import '../services/gemma_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';

class AssistantProvider extends ChangeNotifier {
  final GemmaService gemmaService;
  final TtsService ttsService;
  final SttService sttService;

  AssistantMode _currentMode = AssistantMode.scene;
  bool _isProcessing = false;
  bool _isModelLoaded = false;
  String _lastResponse = '';
  String _statusMessage = 'Initializing...';
  final List<AnalysisResult> _history = [];

  AssistantMode get currentMode => _currentMode;
  bool get isProcessing => _isProcessing;
  bool get isModelLoaded => _isModelLoaded;
  String get lastResponse => _lastResponse;
  String get statusMessage => _statusMessage;
  List<AnalysisResult> get history => List.unmodifiable(_history);

  AssistantProvider({
    required this.gemmaService,
    required this.ttsService,
    required this.sttService,
  });

  Future<void> initialize() async {
    try {
      _statusMessage = 'Loading Gemma 3...';
      notifyListeners();

      await ttsService.initialize();
      await gemmaService.loadModel();

      _isModelLoaded = true;
      _statusMessage = 'Ready';
      notifyListeners();

      await ttsService.speak('Vision Assistant ready. Tap anywhere to analyse your surroundings.');
    } catch (e) {
      _isModelLoaded = false;
      _statusMessage = 'Model failed to load: $e';
      notifyListeners();
      await ttsService.speak('Model failed to load. Please restart the app.');
    }
  }

  void setMode(AssistantMode mode) {
    _currentMode = mode;
    notifyListeners();
    
    final modeName = mode.name[0].toUpperCase() + mode.name.substring(1);
    ttsService.speak('$modeName mode activated');
  }

  Future<void> analyzeImage(Uint8List imageBytes) async {
    if (_isProcessing) return;
    
    _isProcessing = true;
    _statusMessage = 'Analyzing...';
    notifyListeners();
    
    try {
      await ttsService.speak('Analyzing image');
      
      final response = await gemmaService.analyzeImage(
        imageBytes,
        _currentMode.name,
      );
      
      _lastResponse = response;
      _statusMessage = 'Ready';
      _isProcessing = false;
      _history.insert(0, AnalysisResult(
        description: response,
        mode: _currentMode,
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      
      await ttsService.speak(response);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception:', '').trim();
      _statusMessage = 'Error: $msg';
      _isProcessing = false;
      notifyListeners();
      // Speak a concise version of the error so the user knows what happened
      if (msg.contains('not loaded') || msg.contains('loadModel')) {
        await ttsService.speak('AI model is not ready yet. Please wait.');
      } else if (msg.contains('not downloaded')) {
        await ttsService.speak('Model not downloaded. Please check your connection and retry setup.');
      } else {
        await ttsService.speak('Could not analyse the image. Please try again.');
      }
    }
  }

  Future<void> startVoiceCommand() async {
    await ttsService.stop();
    await ttsService.speak('Listening for command');
    
    await sttService.startListening(
      onResult: (text) => _handleVoiceCommand(text),
      onDone: () => notifyListeners(),
    );
  }

  void _handleVoiceCommand(String command) {
    final lower = command.toLowerCase();
    
    if (lower.contains('scene') || lower.contains('describe')) {
      setMode(AssistantMode.scene);
    } else if (lower.contains('navigate') || lower.contains('walk')) {
      setMode(AssistantMode.navigation);
    } else if (lower.contains('text') || lower.contains('read')) {
      setMode(AssistantMode.text);
    } else if (lower.contains('object') || lower.contains('find')) {
      setMode(AssistantMode.objects);
    } else if (lower.contains('quick') || lower.contains('fast')) {
      setMode(AssistantMode.quick);
    } else if (lower.contains('help')) {
      ttsService.speak(
        'Available commands: Scene description, Navigation, Read text, Find objects, Quick summary. '
        'Tap the screen to analyze what the camera sees.'
      );
    } else {
      ttsService.speak('Command not recognized. Say help for available commands.');
    }
  }

  void repeatLastResponse() {
    if (_lastResponse.isNotEmpty) {
      ttsService.speak(_lastResponse);
    } else {
      ttsService.speak('No previous response to repeat');
    }
  }

  @override
  void dispose() {
    gemmaService.dispose();
    ttsService.dispose();
    sttService.dispose();
    super.dispose();
  }
}
