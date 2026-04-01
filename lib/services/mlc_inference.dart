import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Platform channel interface for MLC LLM native inference
class MlcInference {
  static const MethodChannel _channel = MethodChannel('mlc_llm_channel');
  
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// Load the model from the given path
  Future<bool> loadModel(String modelPath) async {
    try {
      final result = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });
      _isLoaded = result == true;
      return _isLoaded;
    } on PlatformException catch (e) {
      print('Failed to load model: ${e.message}');
      return false;
    }
  }

  /// Analyze image and return description
  Future<String> analyzeImage(Uint8List imageBytes, String prompt) async {
    if (!_isLoaded) {
      throw Exception('Model not loaded');
    }
    
    try {
      final result = await _channel.invokeMethod('analyzeImage', {
        'imageBytes': imageBytes,
        'prompt': prompt,
      });
      return result as String;
    } on PlatformException catch (e) {
      throw Exception('Inference failed: ${e.message}');
    }
  }

  /// Generate text response
  Future<String> generateText(String prompt) async {
    if (!_isLoaded) {
      throw Exception('Model not loaded');
    }
    
    try {
      final result = await _channel.invokeMethod('generateText', {
        'prompt': prompt,
      });
      return result as String;
    } on PlatformException catch (e) {
      throw Exception('Generation failed: ${e.message}');
    }
  }

  /// Check if model is loaded
  Future<bool> checkModelLoaded() async {
    try {
      final result = await _channel.invokeMethod('isModelLoaded');
      _isLoaded = result == true;
      return _isLoaded;
    } catch (e) {
      return false;
    }
  }

  /// Unload model to free memory
  Future<void> unloadModel() async {
    try {
      await _channel.invokeMethod('unloadModel');
      _isLoaded = false;
    } catch (e) {
      print('Failed to unload model: $e');
    }
  }
}
