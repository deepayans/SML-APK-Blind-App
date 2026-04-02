import 'dart:typed_data';
import 'model_downloader.dart';
import 'mlc_inference.dart';

/// Coordinates image analysis using the native plugin.
///
/// The native plugin (MlcLlmPlugin.kt) uses:
///   - ML Kit  → always-on, zero download, offline image understanding
///   - Gemma 2B via MediaPipe  → optional, richer descriptions
///
/// This service reflects that: [loadModel] is optional (the app works
/// without it), and [analyzeImage] always returns a real description.
class GemmaService {
  final MlcInference _inference = MlcInference();
  bool _isLoaded = false;

  /// Whether the optional Gemma LLM is loaded.
  bool get isLoaded => _isLoaded;

  /// True if Gemma model file has been downloaded.
  Future<bool> needsModelDownload() async =>
      !(await ModelDownloader.isModelDownloaded());

  /// Optionally load the Gemma LLM for richer descriptions.
  /// Safe to skip — ML Kit handles inference without it.
  Future<void> loadModel() async {
    final modelPath = await ModelDownloader.getModelPath();
    try {
      final loaded = await _inference.loadModel(modelPath);
      _isLoaded = loaded;
    } catch (e) {
      // Gemma failed to load — that's OK, ML Kit still works.
      _isLoaded = false;
      // Re-throw only if the file exists but failed, so the caller can log it.
      if (!(await needsModelDownload())) rethrow;
    }
  }

  /// Analyse [imageBytes] for the given [mode].
  ///
  /// Always returns a real result — ML Kit handles it even if Gemma isn't loaded.
  Future<String> analyzeImage(Uint8List imageBytes, String mode) async {
    final prompt = _buildPrompt(mode);
    return await _inference.analyzeImage(imageBytes, prompt);
  }

  String _buildPrompt(String mode) {
    switch (mode.toLowerCase()) {
      case 'scene':
        return 'Describe this scene in detail for a visually impaired person. '
            'Include all visible objects, their positions (left, right, centre, '
            'near, far), lighting, and any potential hazards.';
      case 'navigation':
        return 'Analyse this image for safe navigation. Identify the clear path, '
            'any obstacles or hazards with positions and distances, '
            'and give concise walking directions.';
      case 'text':
        return 'Read and transcribe every piece of text visible in this image. '
            'Include signs, labels, screens, and handwriting.';
      case 'objects':
        return 'List every distinct object visible with its approximate position '
            '(left/centre/right, near/far) and a brief description.';
      case 'quick':
        return 'In one sentence, state the most important thing a blind person '
            'needs to know about this image right now.';
      default:
        return 'Describe what you see in this image for someone who cannot see it.';
    }
  }

  void dispose() => _inference.unloadModel();
}
