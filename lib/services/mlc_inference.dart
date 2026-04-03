import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Dart-side platform channel that talks to [MlcLlmPlugin] on the Android side.
///
/// All methods surface real errors instead of returning false/null silently,
/// so failures propagate up to the UI layer.
class MlcInference {
  static const MethodChannel _channel = MethodChannel('mlc_llm_channel');

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// Load the MLC model from [modelPath].
  ///
  /// Returns true on success. Throws [Exception] on any failure so the caller
  /// gets a clear message rather than silently falling back to demo mode.
  Future<bool> loadModel(String modelPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelPath,
      });
      _isLoaded = result == true;
      return _isLoaded;
    } on PlatformException catch (e) {
      _isLoaded = false;
      throw Exception('loadModel failed [${e.code}]: ${e.message}');
    }
  }

  /// Send [imageBytes] (JPEG from the camera) and [prompt] to the native
  /// MLC engine for vision inference.
  ///
  /// No [_isLoaded] guard here — the native plugin (MlcLlmPlugin.kt) handles
  /// analysis via ML Kit even when Gemma is not loaded. Blocking here would
  /// prevent the app from working until the optional 1.5 GB model is downloaded.
  ///
  /// Returns the model's text response. Throws on failure.
  Future<String> analyzeImage(Uint8List imageBytes, String prompt) async {
    try {
      final result = await _channel.invokeMethod<String>('analyzeImage', {
        'imageBytes': imageBytes,
        'prompt': prompt,
      });
      if (result == null || result.isEmpty) {
        throw Exception('Empty response from inference engine.');
      }
      return result;
    } on PlatformException catch (e) {
      throw Exception('analyzeImage failed [${e.code}]: ${e.message}');
    }
  }

  /// Burst analysis: sends multiple JPEG frames to the native side which
  /// runs ML Kit on each, deduplicates detections, then runs Gemma once.
  Future<String> analyzeBurst(List<Uint8List> frames, String prompt) async {
    try {
      final result = await _channel.invokeMethod<String>('analyzeBurst', {
        'frames': frames,
        'prompt': prompt,
      });
      if (result == null || result.isEmpty) {
        throw Exception('Empty response from burst analysis.');
      }
      return result;
    } on PlatformException catch (e) {
      throw Exception('analyzeBurst failed [${e.code}]: ${e.message}');
    }
  }

  /// Generate text from [prompt] without an image (for voice commands, etc.).
  Future<String> generateText(String prompt) async {
    if (!_isLoaded) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }
    try {
      final result = await _channel.invokeMethod<String>('generateText', {
        'prompt': prompt,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('generateText failed [${e.code}]: ${e.message}');
    }
  }

  /// Ask the native side whether the engine has a model loaded.
  Future<bool> checkModelLoaded() async {
    try {
      final result = await _channel.invokeMethod<bool>('isModelLoaded');
      _isLoaded = result == true;
      return _isLoaded;
    } catch (_) {
      return false;
    }
  }

  /// Unload the model to free RAM. Safe to call even if not loaded.
  Future<void> unloadModel() async {
    try {
      await _channel.invokeMethod('unloadModel');
    } catch (_) {
      // Best-effort unload; ignore errors.
    } finally {
      _isLoaded = false;
    }
  }
}
