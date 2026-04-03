import 'dart:typed_data';
import 'model_downloader.dart';
import 'mlc_inference.dart';

/// Orchestrates the two-stage on-device AI pipeline:
///
///   Stage 1 — ML Kit (always ready, no download):
///     Object Detection + Text Recognition extract structured scene data.
///
///   Stage 2 — Gemma 2B via MediaPipe (after first-launch download):
///     Takes ML Kit detections as a structured prompt, returns fluent
///     natural-language descriptions tailored to each analysis mode.
///
/// The combination gives high accuracy: ML Kit ensures reliable perception,
/// Gemma ensures natural, context-aware language output.
class GemmaService {
  final MlcInference _inference = MlcInference();
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<bool> needsModelDownload() async =>
      !(await ModelDownloader.isModelDownloaded());

  /// Load Gemma 2B from the downloaded model directory.
  /// Throws if the model file is missing.
  Future<void> loadModel() async {
    if (await needsModelDownload()) {
      throw Exception('Gemma model not downloaded yet.');
    }
    final modelPath = await ModelDownloader.getModelPath();
    final loaded = await _inference.loadModel(modelPath);
    if (!loaded) {
      throw Exception(
          'MediaPipe failed to load Gemma. '
          'Ensure the device is arm64 and has enough RAM (4 GB+ recommended).');
    }
    _isLoaded = true;
  }

  /// Analyse [imageBytes] for the given [mode].
  ///
  /// Pipeline:
  ///   ML Kit → structured detections → Gemma 2B prompt → fluent description
  ///
  /// If Gemma is not loaded, ML Kit's structured output is returned as-is.
  Future<String> analyzeImage(Uint8List imageBytes, String mode) async {
    final prompt = _modePrompt(mode);
    // The native plugin handles the full pipeline (ML Kit + Gemma if loaded).
    return await _inference.analyzeImage(imageBytes, prompt);
  }

  /// Burst analysis: sends multiple frames to the native plugin which runs
  /// ML Kit on each, merges all detections, then runs Gemma once.
  Future<String> analyzeBurst(List<Uint8List> frames, String mode) async {
    final prompt = _modePrompt(mode);
    return await _inference.analyzeBurst(frames, prompt);
  }

  String _modePrompt(String mode) {
    switch (mode.toLowerCase()) {
      case 'scene':
        return 'Describe this scene for a visually impaired person, noting positions and any hazards.';
      case 'navigation':
        return 'Describe for navigation: identify obstacles with positions and the safest path forward.';
      case 'text':
        return 'Read all visible text aloud, including signs, labels, and any other writing.';
      case 'objects':
        return 'List every visible object with its position (left, centre, right) and distance (near, far).';
      case 'quick':
        return 'State in one sentence the single most important thing a blind person needs to know right now.';
      default:
        return 'Describe what you see for someone who cannot see it.';
    }
  }

  void dispose() => _inference.unloadModel();
}
